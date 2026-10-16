import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../data/member_failure.dart';
import '../../memberships/providers/payment_providers.dart';
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

  void apply({required String search, MemberStatus? status, String? gender}) {
    final next = MemberListQuery(
      search: search,
      status: status,
      gender: gender,
    );
    if (state.page == next.page &&
        state.search == next.search &&
        state.status == next.status &&
        state.gender == next.gender) {
      return;
    }
    state = next;
  }

  void page(int page) {
    if (state.page != page) state = state.withPage(page);
  }
}

final memberQueryProvider =
    NotifierProvider<MemberQueryController, MemberListQuery>(
      MemberQueryController.new,
    );

class MembersController extends AsyncNotifier<MembersPage?> {
  Future<void>? _reload;
  Object? _reloadScope;
  @override
  Future<MembersPage?> build() async {
    final context = ref.watch(adminGymProvider);
    final query = ref.watch(memberQueryProvider);
    if (context == null) return null;
    final repository = ref.watch(memberRepositoryProvider);
    if (query.gender == null) return repository.list(context.gymId, query);
    // Filter all search results before local pagination, so matches on later
    // server pages are not lost. Never send an unsupported gender parameter.
    final matches = <MemberProfile>[];
    var page = 1;
    while (true) {
      if (!ref.mounted ||
          ref.read(adminGymProvider) != context ||
          ref.read(memberQueryProvider) != query) {
        return null;
      }
      final result = await repository.list(
        context.gymId,
        MemberListQuery(
          page: page,
          limit: 100,
          search: query.search,
          status: query.status,
        ),
      );
      matches.addAll(
        result.members.where((member) => member.gender == query.gender),
      );
      if (page * 100 >= result.pagination.total) break;
      if (page == 10000) {
        throw const MemberFailure(
          'This list is too large to filter. Narrow your search.',
        );
      }
      page++;
    }
    final offset = (query.page - 1) * query.limit;
    return MembersPage(
      matches.skip(offset).take(query.limit).toList(),
      Pagination.fromJson({
        'page': query.page,
        'limit': query.limit,
        'total': matches.length,
      }),
    );
  }

  Future<void> reload() {
    final scope = (
      ref.read(adminGymProvider),
      ref.read(memberQueryProvider),
      ref.read(memberRepositoryProvider),
      ref.read(authRepositoryProvider).revision,
    );
    final pending = _reload;
    if (pending != null && _reloadScope == scope) return pending;
    _reloadScope = scope;
    ref.invalidateSelf();
    late final Future<void> flight;
    flight = future.then<void>((_) {}).whenComplete(() {
      if (identical(_reload, flight)) _reload = null;
    });
    return _reload = flight;
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

// Share only active reads, not saved financial results. Each consumer clears
// the flight map on disposal/invalidation so explicit refreshes start fresh.
class _HistoryReads {
  _HistoryReads(this.read);
  final Future<MembershipHistory> Function(int) read;
  final _flights = <int, Future<MembershipHistory>>{};
  Future<MembershipHistory> page(int page) {
    final pending = _flights[page];
    if (pending != null) return pending;
    late final Future<MembershipHistory> flight;
    flight = read(page).whenComplete(() {
      if (identical(_flights[page], flight)) _flights.remove(page);
    });
    return _flights[page] = flight;
  }

  void clear() => _flights.clear();
}

final _historyReadsProvider = Provider.autoDispose
    .family<_HistoryReads, MemberScope>((ref, scope) {
      final repository = ref.watch(memberRepositoryProvider);
      final auth = ref.watch(authRepositoryProvider);
      final revision = ref.watch(
        sessionControllerProvider.select((_) => auth.revision),
      );
      final gym = ref.watch(adminGymProvider);
      final reads = _HistoryReads((page) async {
        void guard() {
          if (!ref.mounted ||
              auth.revision != revision ||
              !matchesScope(ref.read(adminGymProvider), scope) ||
              ref.read(adminGymProvider) != gym) {
            throw const MemberFailure(
              'The account or gym changed. Reopen this member.',
            );
          }
        }

        guard();
        final history = await repository.memberships(
          scope.gymId,
          scope.memberId,
          page,
        );
        guard();
        return history;
      });
      ref.onDispose(reads.clear);
      return reads;
    });

final memberHistoryProvider = FutureProvider.autoDispose
    .family<MembershipHistory?, HistoryRequest>((ref, request) {
      if (!matchesScope(ref.watch(adminGymProvider), request.scope)) {
        return null;
      }
      final reads = ref.watch(_historyReadsProvider(request.scope));
      ref.onDispose(reads.clear);
      return reads.page(request.page);
    }, retry: (_, _) => null);
// Aggregate only this member's saved history, not the whole gym's dues list.
final memberMembershipsProvider = FutureProvider.autoDispose
    .family<List<Membership>?, MemberScope>((ref, scope) async {
      final gym = ref.watch(adminGymProvider);
      final repository = ref.watch(memberRepositoryProvider);
      if (!matchesScope(gym, scope)) return null;
      final reads = ref.watch(_historyReadsProvider(scope));
      ref.onDispose(reads.clear);
      void guard() {
        if (!ref.mounted ||
            ref.read(adminGymProvider) != gym ||
            !identical(repository, ref.read(memberRepositoryProvider))) {
          throw const MemberFailure(
            'The account or gym changed. Reopen this member.',
          );
        }
      }

      return repository.allMemberships(
        scope.gymId,
        scope.memberId,
        guard: guard,
        readPage: reads.page,
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
        ref.invalidate(memberProfileProvider(scope));
        ref.invalidate(outstandingDuesProvider);
        ref.invalidate(revenueDetailsProvider);
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
