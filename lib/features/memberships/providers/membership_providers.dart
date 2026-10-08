import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../../members/data/member_failure.dart';
import '../../members/providers/member_providers.dart';
import '../data/billing_failure.dart';
import '../data/membership_repository.dart';
import '../models/billing_models.dart';

final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => DioMembershipRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(memberRepositoryProvider),
  ),
);

typedef BillingRequest = ({MemberScope scope, int page});
final activePlansProvider = FutureProvider.autoDispose
    .family<BillingPage<MembershipPlan>?, BillingRequest>((ref, request) {
      if (!matchesScope(ref.watch(adminGymProvider), request.scope)) {
        return null;
      }
      return ref
          .watch(membershipRepositoryProvider)
          .plans(request.scope.gymId, request.page);
    }, retry: (_, _) => null);
final paymentHistoryProvider = FutureProvider.autoDispose
    .family<BillingPage<RecordedPayment>?, BillingRequest>((ref, request) {
      if (!matchesScope(ref.watch(adminGymProvider), request.scope)) {
        return null;
      }
      return ref
          .watch(membershipRepositoryProvider)
          .payments(request.scope.gymId, request.scope.memberId, request.page);
    }, retry: (_, _) => null);

class BillingMutationController extends AsyncNotifier<BillingResult?> {
  BillingMutationController(this.scope);
  final MemberScope scope;
  bool _busy = false;
  bool _uncertain = false;
  int? _sessionRevision;
  BillingFailure? _failure;
  @override
  BillingResult? build() {
    final context = ref.watch(adminGymProvider);
    final revision = ref.read(authRepositoryProvider).revision;
    if (_sessionRevision != revision) {
      _sessionRevision = revision;
      _uncertain = false;
      _failure = null;
    }
    if (matchesScope(context, scope) && _uncertain && _failure != null) {
      throw _failure!;
    }
    return null;
  }

  bool _current() =>
      ref.mounted &&
      matchesScope(ref.read(adminGymProvider), scope) &&
      ref.read(sessionControllerProvider) is SessionAuthenticated;
  void _invalidate() {
    ref.invalidate(memberSummaryProvider(scope));
    // All cached history pages/details may shift after a mutation.
    ref.invalidate(memberHistoryProvider);
    ref.invalidate(membershipDetailProvider);
    ref.invalidate(paymentHistoryProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<BillingResult?> _run(
    Future<BillingResult> Function(MembershipRepository) operation,
  ) async {
    if (_busy || _uncertain || !_current()) return null;
    final auth = ref.read(authRepositoryProvider);
    final revision = auth.revision;
    bool current() =>
        _current() &&
        identical(ref.read(authRepositoryProvider), auth) &&
        auth.revision == revision;
    _busy = true;
    state = const AsyncLoading();
    try {
      final result = await operation(ref.read(membershipRepositoryProvider));
      if (!current()) return null;
      _invalidate();
      state = AsyncData(result);
      return result;
    } catch (error, stack) {
      if (current()) {
        final failure = error is BillingFailure
            ? error
            : error is MemberFailure
            ? BillingFailure(error.message)
            : const BillingFailure(
                'The outcome is uncertain. Check membership and payment history before another attempt.',
                uncertain: true,
              );
        _uncertain = failure.uncertain;
        _failure = failure;
        state = AsyncError(failure, stack);
      }
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<BillingResult?> purchase(PurchaseDraft draft) => _run(
    (repository) => repository.purchase(scope.gymId, scope.memberId, draft),
  );
  Future<BillingResult?> cancel(String id, String reason) => _run(
    (repository) => repository.cancel(scope.gymId, scope.memberId, id, reason),
  );
  Future<BillingResult?> renew(String id) =>
      _run((repository) => repository.renew(scope.gymId, scope.memberId, id));

  /// Explicit recheck only, never a resubmission. Both histories must load before
  /// unlocking another manual review. Kept across screen navigation per scope.
  Future<bool> recheck() async {
    if (_busy || !_current()) return false;
    final auth = ref.read(authRepositoryProvider);
    final revision = auth.revision;
    bool current() =>
        _current() &&
        identical(ref.read(authRepositoryProvider), auth) &&
        auth.revision == revision;
    _busy = true;
    state = const AsyncLoading();
    try {
      final request = (scope: scope, page: 1);
      ref.invalidate(memberHistoryProvider(request));
      ref.invalidate(paymentHistoryProvider(request));
      final memberships = await ref.read(memberHistoryProvider(request).future);
      final payments = await ref.read(paymentHistoryProvider(request).future);
      if (!current() || memberships == null || payments == null) return false;
      _invalidate();
      _uncertain = false;
      _failure = null;
      state = const AsyncData(null);
      return true;
    } catch (_, stack) {
      if (current()) {
        _uncertain = true;
        _failure = const BillingFailure(
          'History could not be checked. Refresh membership and payment history before another attempt.',
          uncertain: true,
        );
        state = AsyncError(
          const BillingFailure(
            'History could not be checked. Refresh membership and payment history before another attempt.',
            uncertain: true,
          ),
          stack,
        );
      }
      return false;
    } finally {
      _busy = false;
    }
  }
}

// Retains an uncertain-write lock if the admin leaves and returns to the screen.
// A new session resets this state; switching gyms preserves an uncertain lock.
// All operations verify the live session and selected gym.
final billingMutationProvider =
    AsyncNotifierProvider.family<
      BillingMutationController,
      BillingResult?,
      MemberScope
    >(BillingMutationController.new, retry: (_, _) => null);
