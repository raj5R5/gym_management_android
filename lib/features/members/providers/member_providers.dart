import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../data/member_failure.dart';
import '../data/member_repository.dart';
import '../models/member_draft.dart';
import '../models/member_models.dart';

typedef MemberScope = ({String userId, String gymId, String memberId});
MemberScope scopeFor(AdminGymContext context, String memberId) =>
    (userId: context.userId, gymId: context.gymId, memberId: memberId);
bool matchesScope(AdminGymContext? context, MemberScope scope) =>
    context?.userId == scope.userId && context?.gymId == scope.gymId;
final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => DioMemberRepository(ref.watch(authenticatedApiClientProvider)),
);

class MemberQueryController extends Notifier<MemberListQuery> {
  @override
  MemberListQuery build() {
    ref.watch(
      adminGymProvider,
    ); // Reset filters/pages on tenant or account change.
    return MemberListQuery();
  }

  void apply({required String search, MemberStatus? status}) =>
      state = MemberListQuery(search: search, status: status);
  void page(int page) => state = state.withPage(page);
}

final memberQueryProvider =
    NotifierProvider<MemberQueryController, MemberListQuery>(
      MemberQueryController.new,
    );

class MembersController extends AsyncNotifier<MembersPage?> {
  @override
  Future<MembersPage?> build() async {
    final context = ref.watch(adminGymProvider);
    final query = ref.watch(memberQueryProvider);
    if (context == null) return null;
    return ref.watch(memberRepositoryProvider).list(context.gymId, query);
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final membersProvider = AsyncNotifierProvider<MembersController, MembersPage?>(
  MembersController.new,
  retry: (_, _) => null,
);
final memberProfileProvider = FutureProvider.autoDispose
    .family<MemberProfile?, MemberScope>((ref, scope) {
      if (!matchesScope(ref.watch(adminGymProvider), scope)) return null;
      return ref
          .watch(memberRepositoryProvider)
          .get(scope.gymId, scope.memberId);
    }, retry: (_, _) => null);
final memberSummaryProvider = FutureProvider.autoDispose
    .family<MemberSummary?, MemberScope>((ref, scope) {
      if (!matchesScope(ref.watch(adminGymProvider), scope)) return null;
      return ref
          .watch(memberRepositoryProvider)
          .summary(scope.gymId, scope.memberId);
    }, retry: (_, _) => null);
typedef HistoryRequest = ({MemberScope scope, int page});
final memberHistoryProvider = FutureProvider.autoDispose
    .family<MembershipHistory?, HistoryRequest>((ref, request) {
      if (!matchesScope(ref.watch(adminGymProvider), request.scope)) {
        return null;
      }
      return ref
          .watch(memberRepositoryProvider)
          .memberships(
            request.scope.gymId,
            request.scope.memberId,
            request.page,
          );
    }, retry: (_, _) => null);
typedef MembershipRequest = ({MemberScope scope, String subscriptionId});
final membershipDetailProvider = FutureProvider.autoDispose
    .family<MembershipDetail?, MembershipRequest>((ref, request) {
      if (!matchesScope(ref.watch(adminGymProvider), request.scope)) {
        return null;
      }
      return ref
          .watch(memberRepositoryProvider)
          .membership(
            request.scope.gymId,
            request.scope.memberId,
            request.subscriptionId,
          );
    }, retry: (_, _) => null);

class MemberMutationController extends AsyncNotifier<MemberProfile?> {
  MemberMutationController(this.scope);
  final MemberScope scope;
  bool _busy = false;
  @override
  MemberProfile? build() {
    ref.watch(adminGymProvider);
    return null;
  }

  bool _current() =>
      ref.mounted &&
      matchesScope(ref.read(adminGymProvider), scope) &&
      ref.read(sessionControllerProvider) is SessionAuthenticated;
  Future<MemberProfile?> save(MemberDraft draft) async {
    if (_busy || !_current()) return null;
    _busy = true;
    state = const AsyncLoading();
    try {
      final repository = ref.read(memberRepositoryProvider);
      final saved = scope.memberId.isEmpty
          ? await repository.onboard(scope.gymId, draft)
          : await repository.update(scope.gymId, scope.memberId, draft);
      // A sent server mutation cannot be recalled, but it must never update a
      // different account/gym's presentation or cache after navigation/logout.
      if (!_current()) return null;
      state = AsyncData(saved);
      ref.invalidate(membersProvider);
      ref.invalidate(dashboardProvider);
      if (scope.memberId.isNotEmpty) {
        ref.invalidate(memberSummaryProvider(scope));
      }
      return saved;
    } catch (error, stack) {
      if (_current()) {
        state = AsyncError(
          error is MemberFailure
              ? error
              : const MemberFailure(
                  'Member could not be saved. Please try again.',
                ),
          stack,
        );
      }
      return null;
    } finally {
      _busy = false;
    }
  }
}

final memberMutationProvider = AsyncNotifierProvider.autoDispose
    .family<MemberMutationController, MemberProfile?, MemberScope>(
      MemberMutationController.new,
      retry: (_, _) => null,
    );
