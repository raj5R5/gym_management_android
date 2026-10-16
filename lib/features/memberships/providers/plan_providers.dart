import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import 'membership_providers.dart';

typedef PlanPageRequest = ({AdminGymContext gym, int page});
typedef PlanScope = ({AdminGymContext gym, String planId});

/// The active-plan endpoint reports the gym-wide total in pagination metadata.
/// No per-page counting, synthetic member scope, or revenue-date dependency.
final activePlanCountProvider = FutureProvider<int?>((ref) async {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  final page = await ref
      .watch(membershipRepositoryProvider)
      .plans(gym.gymId, 1);
  return page.pagination.total;
}, retry: (_, _) => null);
final managedPlansProvider = FutureProvider.autoDispose
    .family<BillingPage<MembershipPlan>?, PlanPageRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(membershipRepositoryProvider)
          .managePlans(request.gym.gymId, request.page);
    }, retry: (_, _) => null);
final activeManagedPlansProvider = FutureProvider.autoDispose
    .family<BillingPage<MembershipPlan>?, PlanPageRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(membershipRepositoryProvider)
          .plans(request.gym.gymId, request.page);
    }, retry: (_, _) => null);
final planDetailProvider = FutureProvider.autoDispose
    .family<MembershipPlan?, PlanScope>((ref, scope) {
      if (ref.watch(adminGymProvider) != scope.gym) return null;
      return ref
          .watch(membershipRepositoryProvider)
          .plan(scope.gym.gymId, scope.planId);
    }, retry: (_, _) => null);

class PlanMutationController extends AsyncNotifier<MembershipPlan?> {
  PlanMutationController(this.scope);
  final PlanScope scope;
  bool _busy = false;
  BillingFailure? _uncertain;
  int? _revision;
  @override
  MembershipPlan? build() {
    final gym = ref.watch(adminGymProvider);
    final revision = ref.read(authRepositoryProvider).revision;
    if (_revision != revision) {
      _revision = revision;
      _uncertain = null;
    }
    if (gym == scope.gym && _uncertain != null) throw _uncertain!;
    return null;
  }

  bool _current(int revision) =>
      ref.mounted &&
      ref.read(adminGymProvider) == scope.gym &&
      ref.read(sessionControllerProvider) is SessionAuthenticated &&
      ref.read(authRepositoryProvider).revision == revision;
  Future<MembershipPlan?> save(PlanDraft draft) async {
    final revision = ref.read(authRepositoryProvider).revision;
    if (_busy || _uncertain != null || !_current(revision)) return null;
    _busy = true;
    state = const AsyncLoading();
    try {
      final plan = await ref
          .read(membershipRepositoryProvider)
          .savePlan(
            scope.gym.gymId,
            draft,
            planId: scope.planId.isEmpty ? null : scope.planId,
          );
      if (!_current(revision)) return null;
      ref.invalidate(managedPlansProvider);
      ref.invalidate(activeManagedPlansProvider);
      ref.invalidate(activePlansProvider);
      ref.invalidate(activePlanCountProvider);
      // The editor keeps its own fresh read until it leaves, preserving input.
      state = AsyncData(plan);
      return plan;
    } catch (error, stack) {
      if (_current(revision)) {
        final failure = error is BillingFailure
            ? error
            : const BillingFailure(
                'The plan save outcome is uncertain. Recheck Membership Plans before another attempt.',
                uncertain: true,
              );
        if (failure.uncertain) _uncertain = failure;
        state = AsyncError(failure, stack);
      }
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> recheck() async {
    final revision = ref.read(authRepositoryProvider).revision;
    if (_busy || !_current(revision)) return;
    _busy = true;
    state = const AsyncLoading();
    try {
      await ref
          .read(membershipRepositoryProvider)
          .managePlans(scope.gym.gymId, 1);
      if (scope.planId.isNotEmpty) {
        await ref
            .read(membershipRepositoryProvider)
            .plan(scope.gym.gymId, scope.planId);
      }
      if (!_current(revision)) return;
      ref.invalidate(managedPlansProvider);
      ref.invalidate(activeManagedPlansProvider);
      ref.invalidate(activePlansProvider);
      ref.invalidate(activePlanCountProvider);
      _uncertain = null;
      state = const AsyncData(null);
    } catch (_, stack) {
      if (_current(revision)) {
        _uncertain = const BillingFailure(
          'Plans could not be checked. Recheck Membership Plans before another attempt.',
          uncertain: true,
        );
        state = AsyncError(_uncertain!, stack);
      }
    } finally {
      _busy = false;
    }
  }
}

final planMutationProvider =
    AsyncNotifierProvider.family<
      PlanMutationController,
      MembershipPlan?,
      PlanScope
    >(PlanMutationController.new, retry: (_, _) => null);
