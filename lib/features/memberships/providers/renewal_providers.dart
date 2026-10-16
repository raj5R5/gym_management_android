import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../../auth/models/session_state.dart';
import '../../members/data/onboarding_secure_storage.dart';
import '../../members/providers/member_providers.dart';
import '../data/billing_failure.dart';
import '../../members/data/member_repository.dart';
import '../models/membership_eligibility.dart';
import '../data/pending_payment_store.dart' show PaymentRecoveryScope;
import '../data/pending_renewal_store.dart';
import '../data/renewal_repository.dart';
import '../models/billing_models.dart';
import '../models/renewal_operation.dart';
import '../models/renewal_preview.dart';
import 'membership_providers.dart';
import 'payment_providers.dart';

final renewalRepositoryProvider = Provider<RenewalRepository>(
  (ref) => DioRenewalRepository(ref.watch(authenticatedApiClientProvider)),
);
final pendingRenewalStoreProvider = Provider(
  (ref) => PendingRenewalStore(
    storage: const OnboardingSecureStorage(recordPrefix: 'gym.payment.v1.'),
    queue: ref.watch(paymentStorageQueueProvider),
  ),
);
typedef SelectedRenewalRequest = ({
  MembershipRequest membership,
  String planId,
});
final selectedRenewalPreviewProvider = FutureProvider.autoDispose
    .family<RenewalPreview?, SelectedRenewalRequest>((ref, request) async {
      final gym = ref.watch(adminGymProvider);
      final repository = ref.watch(renewalRepositoryProvider);
      if (!matchesScope(gym, request.membership.scope)) return null;
      final result = await repository.preview(
        gym!.gymId,
        request.membership.scope.memberId,
        request.membership.subscriptionId,
        request.planId,
      );
      if (!ref.mounted ||
          ref.read(adminGymProvider) != gym ||
          !identical(repository, ref.read(renewalRepositoryProvider))) {
        return null;
      }
      return result;
    }, retry: (_, _) => null);

/// Uses the same native durability adapter and serialized storage/submission
/// queues as installment recovery; existing installment records stay untouched.
class RenewalController extends AsyncNotifier<RenewalResult?> {
  RenewalController(this.request);
  final MembershipRequest request;
  PendingRenewal? _pending, _prepared;
  PaymentRecoveryScope? _scope;
  bool _busy = false, _ready = false;
  CancelToken? _cancel;
  bool get busy => _busy;
  PendingRenewal? get saved => _pending;
  RenewalResult? get confirmed => _current() ? _pending?.result : null;
  bool get ready => _ready;
  bool get canStart =>
      _ready && _prepared == null && (_pending == null || _pending!.rejected);
  bool get canRetry =>
      _prepared != null ||
      (_pending != null &&
          _pending!.result == null &&
          !_pending!.conflict &&
          !_pending!.rejected);
  @override
  Future<RenewalResult?> build() async {
    final gym = ref.watch(adminGymProvider);
    final config = ref.watch(appConfigProvider);
    ref.watch(authRepositoryProvider);
    ref.listen(sessionControllerProvider, (_, session) {
      if (session is! SessionAuthenticated &&
          !(session is SessionLoading &&
              session.operation == SessionOperation.refreshing)) {
        _cancel?.cancel();
      }
    });
    ref.onDispose(() => _cancel?.cancel());
    _ready = false;
    if (!matchesScope(gym, request.scope)) return null;
    final scope = PaymentRecoveryScope.fromConfig(
      config,
      userId: request.scope.userId,
      gymId: request.scope.gymId,
      memberId: request.scope.memberId,
      subscriptionId: request.subscriptionId,
    );
    if (_scope != null && !_scope!.matches(scope)) _pending = _prepared = null;
    _scope = scope;
    final actual = await ref.read(pendingRenewalStoreProvider).read(scope);
    if (!_current() || _scope?.matches(scope) != true) return null;
    _pending = actual;
    _ready = true;
    if (actual?.result != null) _refresh();
    return actual?.result;
  }

  bool _current() {
    if (!ref.mounted ||
        !matchesScope(ref.read(adminGymProvider), request.scope) ||
        ref.read(sessionControllerProvider) is! SessionAuthenticated ||
        _scope == null) {
      return false;
    }
    final config = ref.read(appConfigProvider);
    return config.environment == _scope!.account.environment &&
        config.apiBaseUrl.toString() == _scope!.account.apiBaseUrl;
  }

  void _check() {
    if (!_current()) {
      throw const BillingFailure(
        'The account, gym or API changed. The saved renewal stays with its original account.',
        uncertain: true,
      );
    }
  }

  void _refresh() {
    ref.invalidate(membersProvider);
    ref.invalidate(memberSummaryProvider(request.scope));
    ref.invalidate(memberHistoryProvider);
    ref.invalidate(memberMembershipsProvider(request.scope));
    ref.invalidate(membershipDetailProvider);
    ref.invalidate(paymentHistoryProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(outstandingDuesProvider);
    ref.invalidate(revenueDetailsProvider);
  }

  Future<RenewalResult?> submit(
    RenewalPreview preview,
    ManualPayment? payment,
  ) async {
    if (_busy) return null;
    _busy = true;
    try {
      if (!_ready) await future;
      _check();
      if (!canStart ||
          preview.gymId != request.scope.gymId ||
          preview.memberId != request.scope.memberId ||
          preview.subscriptionId != request.subscriptionId) {
        return null;
      }
      // Fresh eligibility applies only to a NEW logical operation. Exact
      // recovery must replay a committed request even when its successor is active.
      final auth = ref.read(authRepositoryProvider);
      final revision = auth.revision;
      final memberships = await ref
          .read(memberRepositoryProvider)
          .allMemberships(
            request.scope.gymId,
            request.scope.memberId,
            guard: () {
              _check();
              if (!identical(auth, ref.read(authRepositoryProvider)) ||
                  auth.revision != revision) {
                throw const BillingFailure(
                  'The session changed. Reopen this membership.',
                );
              }
            },
          );
      if (blockingMembership(memberships) != null) {
        ref.invalidate(memberMembershipsProvider(request.scope));
        throw const BillingFailure(activeMembershipMessage);
      }
      _prepared = PendingRenewal(
        scope: _scope!,
        createdAt: DateTime.now().toUtc(),
        request: RenewalOperationRequest.fromPreview(
          preview,
          ref.read(paymentKeyFactoryProvider)(),
          payment,
        ),
      );
      return await _run();
    } catch (error, stack) {
      if (_current()) state = AsyncError(error, stack);
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<RenewalResult?> retrySaved() async {
    if (_busy || !_current() || !canRetry) return null;
    _busy = true;
    try {
      return await _run();
    } finally {
      _busy = false;
    }
  }

  Future<void> recheck() async {
    if (_busy || !_current()) return;
    _busy = true;
    state = const AsyncLoading();
    try {
      final actual = await ref.read(pendingRenewalStoreProvider).read(_scope!);
      _check();
      _pending = actual;
      _ready = true;
      if (actual != null && _prepared?.same(actual) == true) _prepared = null;
      state = AsyncData(actual?.result);
    } catch (error, stack) {
      _ready = false;
      if (_current()) state = AsyncError(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<void> acknowledge() async {
    if (_busy || !_current() || confirmed == null) return;
    _busy = true;
    final actual = _pending!;
    final auth = ref.read(authRepositoryProvider);
    final revision = auth.revision;
    void guard() {
      _check();
      if (auth.revision != revision ||
          !identical(auth, ref.read(authRepositoryProvider)) ||
          _scope?.matches(actual.scope) != true) {
        throw const BillingFailure(
          'Session changed. Keep the saved renewal confirmation.',
          uncertain: true,
        );
      }
    }

    state = const AsyncLoading();
    try {
      await ref.read(paymentSubmissionQueueProvider).run(() async {
        guard();
        await ref
            .read(pendingRenewalStoreProvider)
            .acknowledge(actual, guard: guard);
        guard();
      });
      _pending = null;
      state = const AsyncData(null);
    } catch (error, stack) {
      if (_current()) state = AsyncError(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<RenewalResult?> _run() async {
    final store = ref.read(pendingRenewalStoreProvider);
    final repository = ref.read(renewalRepositoryProvider);
    final auth = ref.read(authRepositoryProvider);
    final revision = auth.revision;
    final scope = _scope!;
    final cancel = CancelToken();
    _cancel = cancel;
    void guard() {
      _check();
      if (cancel.isCancelled ||
          auth.revision != revision ||
          !identical(auth, ref.read(authRepositoryProvider)) ||
          _scope?.matches(scope) != true ||
          !identical(store, ref.read(pendingRenewalStoreProvider)) ||
          !identical(repository, ref.read(renewalRepositoryProvider))) {
        throw const BillingFailure(
          'Session changed. Recover the original saved renewal.',
          uncertain: true,
        );
      }
    }

    state = const AsyncLoading();
    try {
      return await ref.read(paymentSubmissionQueueProvider).run(() async {
        guard();
        var actual = await store.read(scope);
        guard();
        if (_prepared case final prepared?) {
          actual = await store.prepare(
            prepared,
            replacing: actual?.rejected == true ? _pending : null,
            guard: guard,
          );
          guard();
          _prepared = null;
        }
        if (actual == null) {
          throw const BillingFailure(
            'No saved renewal found. Recheck before starting.',
            uncertain: true,
          );
        }
        _pending = actual;
        if (actual.result != null) {
          _refresh();
          state = AsyncData(actual.result);
          return actual.result;
        }
        final dispatch = await store.dispatch(actual, guard: guard);
        guard();
        _pending = dispatch;
        final RenewalResult result;
        try {
          result = await repository.complete(
            request.scope.gymId,
            request.scope.memberId,
            request.subscriptionId,
            dispatch.request,
            cancelToken: cancel,
          );
          guard();
          dispatch.request.validateResult(
            result,
            gymId: request.scope.gymId,
            memberId: request.scope.memberId,
            predecessorId: request.subscriptionId,
          );
        } catch (error) {
          guard();
          final failure = error is BillingFailure
              ? error
              : const BillingFailure(
                  'Renewal outcome is uncertain. Recover the saved renewal.',
                  uncertain: true,
                );
          if (failure.code == 'IDEMPOTENCY_KEY_CONFLICT' &&
              failure.httpStatus == 409) {
            _pending = await store.outcome(
              dispatch,
              RenewalAttempt(
                RenewalOutcome.conflict,
                code: failure.code,
                status: 409,
              ),
              guard: guard,
            );
          } else if (!failure.uncertain &&
              failure.code != null &&
              renewalRejections[failure.code] == failure.httpStatus) {
            _pending = await store.outcome(
              dispatch,
              RenewalAttempt(
                RenewalOutcome.rejected,
                code: failure.code,
                status: failure.httpStatus,
              ),
              guard: guard,
            );
          }
          guard();
          throw BillingFailure(
            failure.message,
            uncertain: !_pending!.rejected,
            code: failure.code,
            httpStatus: failure.httpStatus,
          );
        }
        _pending = await store.outcome(
          dispatch,
          RenewalAttempt(RenewalOutcome.confirmed),
          result: result,
          guard: guard,
        );
        guard();
        _refresh();
        state = AsyncData(_pending!.result);
        return _pending!.result;
      });
    } catch (error, stack) {
      if (!_current()) return null;
      try {
        final actual = await store.read(scope);
        guard();
        if (actual != null) {
          _pending = actual;
          if (_prepared?.same(actual) == true) _prepared = null;
          if (actual.result != null) {
            _refresh();
            state = AsyncData(actual.result);
            return actual.result;
          }
        }
      } catch (_) {
        _ready = false;
      }
      if (_current()) {
        state = AsyncError(
          error is BillingFailure
              ? error
              : const BillingFailure(
                  'Saving the renewal outcome failed. Recover the saved operation; do not renew again.',
                  uncertain: true,
                ),
          stack,
        );
      }
      return null;
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }
}

final renewalControllerProvider =
    AsyncNotifierProvider.family<
      RenewalController,
      RenewalResult?,
      MembershipRequest
    >(RenewalController.new, retry: (_, _) => null);

final renewalPreviousPlanProvider = FutureProvider.autoDispose
    .family<MembershipPlan?, MembershipRequest>((ref, request) async {
      final gym = ref.watch(adminGymProvider);
      final repository = ref.watch(membershipRepositoryProvider);
      if (!matchesScope(gym, request.scope)) return null;
      final detail = await ref.watch(membershipDetailProvider(request).future);
      if (detail == null) return null;
      try {
        final plan = await repository.plan(
          request.scope.gymId,
          detail.subscription.planId,
        );
        if (!ref.mounted ||
            ref.read(adminGymProvider) != gym ||
            plan.status != 'active') {
          return null;
        }
        return plan;
      } on BillingFailure catch (error) {
        if (error.code == 'PLAN_NOT_FOUND') return null;
        rethrow;
      }
    }, retry: (_, _) => null);
