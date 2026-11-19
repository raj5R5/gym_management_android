import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/member_overview_repository.dart';
import '../models/member_overview.dart';

final memberOverviewRepositoryProvider = Provider<MemberOverviewRepository>(
  (ref) =>
      DioMemberOverviewRepository(ref.watch(authenticatedApiClientProvider)),
);

/// Members tab state: filter chip, search text and page.
class MemberOverviewQueryController extends Notifier<MemberOverviewQuery> {
  @override
  MemberOverviewQuery build() {
    // A different gym or account starts from the first page of all members.
    ref.watch(adminGymProvider);
    return const MemberOverviewQuery();
  }

  void select(MemberOverviewFilter filter) =>
      state = MemberOverviewQuery(filter: filter, search: state.search);
  void search(String text) =>
      state = MemberOverviewQuery(filter: state.filter, search: text.trim());
  void page(int page) => state = MemberOverviewQuery(
    filter: state.filter,
    search: state.search,
    page: page,
  );
}

final memberOverviewQueryProvider =
    NotifierProvider<MemberOverviewQueryController, MemberOverviewQuery>(
      MemberOverviewQueryController.new,
    );

/// Any overview query for the selected gym (dashboard to-do lists use small limits).
final memberOverviewProvider = FutureProvider.autoDispose
    .family<MemberOverviewPage?, MemberOverviewQuery>((ref, query) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(memberOverviewRepositoryProvider).list(gym.gymId, query);
    }, retry: (_, _) => null);

/// Refresh every overview view after a payment, renewal or member change.
void invalidateMemberOverview(WidgetRef ref) =>
    ref.invalidate(memberOverviewProvider);
