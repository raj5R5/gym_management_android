import 'dart:math';
import '../../members/providers/member_overview_providers.dart';
import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../members/data/onboarding_secure_storage.dart';
import '../../members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../data/pending_payment_store.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../../members/providers/member_providers.dart';
import '../data/billing_failure.dart';
import '../data/payment_repository.dart';
import '../data/outstanding_dues_repository.dart';
import '../models/billing_models.dart';
import 'membership_providers.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => DioPaymentRepository(ref.watch(authenticatedApiClientProvider)),
);
final outstandingDuesRepositoryProvider = Provider(
  (ref) => OutstandingDuesRepository(ref.watch(memberRepositoryProvider)),
);
final outstandingDuesProvider = FutureProvider.autoDispose<OutstandingDues?>((
  ref,
) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  final repository = ref.watch(outstandingDuesRepositoryProvider);
  return repository.load(
    gym.gymId,
    current: () =>
        ref.mounted &&
        ref.read(adminGymProvider) == gym &&
        identical(ref.read(outstandingDuesRepositoryProvider), repository),
  );
}, retry: (_, _) => null);
typedef RevenueRequest = ({
  AdminGymContext gym,
  String from,
  String to,
  int page,
});
final revenueDetailsProvider = FutureProvider.autoDispose
    .family<RevenuePage?, RevenueRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(paymentRepositoryProvider)
          .revenue(
            request.gym.gymId,
            DashboardQuery.range(
              CalendarDate.parse(request.from),
              CalendarDate.parse(request.to),
            ),
            request.page,
          );
    }, retry: (_, _) => null);

/// Reuse server timezone metadata, never the device zone or a guessed offset.
final paymentTimezoneProvider = FutureProvider.autoDispose
    .family<String?, AdminGymContext>((ref, gym) async {
      if (ref.watch(adminGymProvider) != gym) return null;
      final dashboard = await ref.watch(dashboardProvider.future);
      if (!ref.mounted || ref.read(adminGymProvider) != gym) return null;
      return dashboard?.period.timezone;
    }, retry: (_, _) => null);

typedef PaymentScope = ({MemberScope member, String subscriptionId});
final paymentKeyFactoryProvider = Provider<String Function()>(
  (ref) => () {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  },
);

final paymentStorageQueueProvider = Provider(
  (ref) => OnboardingOperationQueue(),
);
final paymentSubmissionQueueProvider = Provider(
  (ref) => OnboardingOperationQueue(),
);
final pendingPaymentStoreProvider = Provider(
  (ref) => PendingPaymentStore(
    storage: const OnboardingSecureStorage(recordPrefix: 'gym.payment.v1.'),
    queue: ref.watch(paymentStorageQueueProvider),
  ),
);

class PaymentCollectionController extends AsyncNotifier<RecordedPayment?> {
  PaymentCollectionController(this.scope);
  final PaymentScope scope;
  PendingPayment? _operation, _prepared;
  PaymentRecoveryScope? _recoveryScope;
  bool _busy = false, _ready = false;
  CancelToken? _activeCancel;
  PaymentRecoveryScope? _activeScope;
  int? _activeRevision;
  bool get busy => _busy;
  RecordedPayment? get confirmed => _current() ? _operation?.result : null;
  PaymentCollection? get savedCollection =>
      _current() ? (_prepared ?? _operation)?.collection : null;
  bool get hasSavedOperation => _operation != null || _prepared != null;
  bool get blocked =>
      !_ready || (_operation?.unresolved ?? false) || _prepared != null;
  bool get canRetry =>
      (_prepared != null ||
      (_operation != null && _operation!.unresolved && !_operation!.conflict));

  @override
  Future<RecordedPayment?> build() async {
    final gym = ref.watch(adminGymProvider);
    final config = ref.watch(appConfigProvider);
    final auth = ref.watch(authRepositoryProvider);
    void cancelIfChanged() {
      final active = _activeScope;
      if (_activeCancel == null || active == null) return;
      final session = auth.state;
      final gym = ref.read(adminGymProvider);
      final currentConfig = ref.read(appConfigProvider);
      final authenticated =
          session is SessionAuthenticated ||
          session is SessionLoading &&
              session.operation == SessionOperation.refreshing;
      if (!authenticated ||
          auth.revision != _activeRevision ||
          gym?.userId != active.account.userId ||
          gym?.gymId != active.account.gymId ||
          currentConfig.environment != active.account.environment ||
          currentConfig.apiBaseUrl.toString() != active.account.apiBaseUrl) {
        _activeCancel?.cancel();
      }
    }

    final subscription = auth.changes.listen((_) => cancelIfChanged());
    ref.listen(adminGymProvider, (_, _) => cancelIfChanged());
    ref.listen(appConfigProvider, (_, _) => cancelIfChanged());
    ref.onDispose(() {
      subscription.cancel();
      _activeCancel?.cancel();
    });
    _ready = false;
    if (!matchesScope(gym, scope.member)) return null;
    try {
      final recoveryScope = PaymentRecoveryScope.fromConfig(
        config,
        userId: scope.member.userId,
        gymId: scope.member.gymId,
        memberId: scope.member.memberId,
        subscriptionId: scope.subscriptionId,
      );
      if (_recoveryScope != null && !_recoveryScope!.matches(recoveryScope)) {
        _operation = _prepared = null;
      }
      _recoveryScope = recoveryScope;
      final operation = await ref
          .read(pendingPaymentStoreProvider)
          .read(recoveryScope);
      if (!_current() || _recoveryScope?.matches(recoveryScope) != true) {
        return null;
      }
      _operation = operation;
      _ready = true;
      if (operation?.result != null) _refresh();
      return operation?.result;
    } catch (error) {
      throw error is BillingFailure
          ? error
          : const BillingFailure(
              'Configure the API connection before checking saved payments.',
              uncertain: true,
            );
    }
  }

  bool _current() {
    if (!ref.mounted ||
        !matchesScope(ref.read(adminGymProvider), scope.member) ||
        ref.read(sessionControllerProvider) is! SessionAuthenticated ||
        _recoveryScope == null) {
      return false;
    }
    final config = ref.read(appConfigProvider);
    return config.environment == _recoveryScope!.account.environment &&
        config.apiBaseUrl.toString() == _recoveryScope!.account.apiBaseUrl;
  }

  void _check() {
    if (!_current()) {
      throw const BillingFailure(
        'The account, gym or API changed. The saved payment is kept for its original account.',
        uncertain: true,
      );
    }
  }

  void _refresh() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(memberOverviewProvider);
    ref.invalidate(outstandingDuesProvider);
    ref.invalidate(revenueDetailsProvider);
    ref.invalidate(memberSummaryProvider(scope.member));
    ref.invalidate(memberHistoryProvider);
    ref.invalidate(memberMembershipsProvider(scope.member));
    ref.invalidate(membershipDetailProvider);
    ref.invalidate(paymentHistoryProvider);
  }

  Future<RecordedPayment?> collect(
    ManualPayment payment,
    int balancePaise,
  ) async {
    if (_busy) return null;
    _busy = true;
    try {
      if (!_ready) {
        await future; // Restoration is mandatory before accepting a fresh request.
      }
      if (!_ready || blocked || confirmed != null || !_current()) return null;
      if (payment.amountPaise > balancePaise) {
        throw const BillingFailure(
          'Payment cannot exceed the remaining balance.',
        );
      }
      _prepared = PendingPayment(
        scope: _recoveryScope!,
        createdAt: DateTime.now().toUtc(),
        collection: PaymentCollection(
          memberId: scope.member.memberId,
          subscriptionId: scope.subscriptionId,
          key: ref.read(paymentKeyFactoryProvider)(),
          payment: payment,
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

  Future<RecordedPayment?> retrySaved() async {
    if (_busy || !_current()) return null;
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
    final checkingScope = _recoveryScope!;
    try {
      final operation = await ref
          .read(pendingPaymentStoreProvider)
          .read(checkingScope);
      _check();
      if (_recoveryScope?.matches(checkingScope) != true) return;
      _operation = operation;
      if (operation != null && _prepared?.sameOperation(operation) == true) {
        _prepared = null;
      }
      _ready = true;
      state = AsyncData(operation?.result);
      if (operation?.result != null) _refresh();
    } catch (error, stack) {
      _ready = false;
      if (_current()) state = AsyncError(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<void> startAnother() async => acknowledge();
  Future<void> acknowledge() async {
    if (_busy || !_current() || _operation?.result == null) return;
    _busy = true;
    final expected = _operation!;
    void guardAcknowledgement() {
      _check();
      if (_recoveryScope?.matches(expected.scope) != true) {
        throw const BillingFailure(
          'The API scope changed. The saved receipt remains in its original scope.',
          uncertain: true,
        );
      }
    }

    state = const AsyncLoading();
    try {
      await ref.read(paymentSubmissionQueueProvider).run(() async {
        _check();
        await ref
            .read(pendingPaymentStoreProvider)
            .acknowledge(expected, guard: guardAcknowledgement);
        _check();
      });
      _operation = null;
      state = const AsyncData(null);
    } catch (error, stack) {
      if (_current()) state = AsyncError(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<RecordedPayment?> _run() async {
    final store = ref.read(pendingPaymentStoreProvider);
    final queue = ref.read(paymentSubmissionQueueProvider);
    final repository = ref.read(paymentRepositoryProvider);
    final auth = ref.read(authRepositoryProvider);
    final revision = auth.revision;
    final operationScope = _recoveryScope!;
    final cancel = CancelToken();
    _activeCancel = cancel;
    _activeScope = operationScope;
    _activeRevision = revision;
    void guard() {
      _check();
      if (cancel.isCancelled ||
          _recoveryScope?.matches(operationScope) != true ||
          !identical(ref.read(authRepositoryProvider), auth) ||
          auth.revision != revision ||
          !identical(ref.read(paymentRepositoryProvider), repository) ||
          !identical(ref.read(pendingPaymentStoreProvider), store)) {
        throw const BillingFailure(
          'The session changed. Recover the saved payment when signed in again.',
          uncertain: true,
        );
      }
    }

    state = const AsyncLoading();
    var sent = false;
    try {
      return await queue.run(() async {
        guard();
        var actual = await store.read(operationScope);
        guard();
        final prepared = _prepared;
        if (prepared != null) {
          actual = await store.prepare(
            prepared,
            replacing: actual?.rejected == true ? _operation : null,
            guard: guard,
          );
          guard();
          _prepared = null;
        }
        if (actual == null) {
          throw const BillingFailure(
            'No saved payment was found. Recheck recovery before recording money.',
            uncertain: true,
          );
        }
        _operation = actual;
        _ready = true;
        if (actual.result != null) {
          _refresh();
          state = AsyncData(actual.result);
          return actual.result;
        }
        if (actual.conflict || actual.rejected) {
          throw const BillingFailure(
            'This saved payment needs verification or correction before another collection.',
            uncertain: true,
          );
        }
        final dispatch = await store.dispatch(actual, guard: guard);
        guard();
        _operation = dispatch;
        final RecordedPayment result;
        try {
          sent = true;
          result = await repository.record(
            scope.member.gymId,
            dispatch.collection,
            cancelToken: cancel,
          );
          guard();
          dispatch.collection.validateResult(
            result,
            scope.member.gymId,
            userId: scope.member.userId,
          );
        } catch (error) {
          guard();
          final failure = error is BillingFailure
              ? error
              : const BillingFailure(
                  'The payment result has not been confirmed. Recover the saved payment.',
                  uncertain: true,
                );
          if (failure.code == 'IDEMPOTENCY_KEY_CONFLICT') {
            _operation = await store.outcome(
              dispatch,
              PaymentAttempt(
                PaymentAttemptOutcome.conflict,
                code: failure.code,
                httpStatus: failure.httpStatus,
              ),
              guard: guard,
            );
          } else if (!failure.uncertain &&
              failure.code != null &&
              paymentRejections.containsKey(failure.code) &&
              paymentRejections[failure.code] == failure.httpStatus) {
            _operation = await store.outcome(
              dispatch,
              PaymentAttempt(
                PaymentAttemptOutcome.rejected,
                code: failure.code,
                httpStatus: failure.httpStatus,
              ),
              guard: guard,
            );
          }
          guard();
          throw BillingFailure(
            failure.message,
            uncertain: !_operation!.rejected,
            code: failure.code,
            httpStatus: failure.httpStatus,
          );
        }
        _operation = await store.outcome(
          dispatch,
          PaymentAttempt(PaymentAttemptOutcome.confirmed),
          result: result,
          guard: guard,
        );
        guard();
        _refresh();
        state = AsyncData(_operation!.result);
        return _operation!.result;
      });
    } catch (error, stack) {
      if (!_current()) return null;
      // Writes may have succeeded then thrown. Only a verified native read can
      // restore confirmation. Ordinary payment history never releases this lock.
      try {
        final actual = await store.read(operationScope);
        guard();
        if (actual != null) {
          _operation = actual;
          if (_prepared?.sameOperation(actual) == true) _prepared = null;
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
        final cause = error is BillingFailure
            ? error
            : const BillingFailure(
                'Saving the payment outcome failed. Recover the original payment; do not record it again.',
                uncertain: true,
              );
        final feedback = !sent
            ? BillingFailure(
                'This payment attempt was not sent. ${cause.message}',
                uncertain: cause.uncertain,
                code: cause.code,
                httpStatus: cause.httpStatus,
              )
            : cause;
        state = AsyncError(feedback, stack);
      }
      return null;
    } finally {
      if (identical(_activeCancel, cancel)) {
        _activeCancel = null;
        _activeScope = null;
        _activeRevision = null;
      }
    }
  }
}

final paymentCollectionProvider =
    AsyncNotifierProvider.family<
      PaymentCollectionController,
      RecordedPayment?,
      PaymentScope
    >(PaymentCollectionController.new, retry: (_, _) => null);
