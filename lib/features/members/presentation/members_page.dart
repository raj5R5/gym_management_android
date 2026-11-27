import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../owner_profile/owner_profile.dart';
import '../models/member_overview.dart';
import '../providers/member_overview_providers.dart';
import 'member_components.dart';
import 'member_list_widgets.dart';
import 'member_overview_widgets.dart';

class MembersPageView extends ConsumerWidget {
  const MembersPageView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    return gym == null
        ? const SizedBox.shrink()
        : _MembersList(key: ValueKey(gym), gym: gym);
  }
}

class _MembersList extends ConsumerStatefulWidget {
  const _MembersList({super.key, required this.gym});
  final AdminGymContext gym;
  @override
  ConsumerState<_MembersList> createState() => _MembersListState();
}

class _MembersListState extends ConsumerState<_MembersList> {
  late final TextEditingController _search;
  MemberOverviewPage? _last;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(memberOverviewQueryProvider).search,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void>? _refreshFlight;

  /// Single-flight: overlapping pull-to-refresh gestures share one reload.
  Future<void> _refresh() {
    final pending = _refreshFlight;
    if (pending != null) return pending;
    late final Future<void> flight;
    flight = _reload().whenComplete(() {
      if (identical(_refreshFlight, flight)) _refreshFlight = null;
    });
    return _refreshFlight = flight;
  }

  Future<void> _reload() async {
    final query = ref.read(memberOverviewQueryProvider);
    ref.invalidate(memberOverviewProvider);
    try {
      await ref.read(memberOverviewProvider(query).future);
    } catch (_) {
      // The error is rendered with a retry action.
    }
  }

  void _applySearch() =>
      ref.read(memberOverviewQueryProvider.notifier).search(_search.text);
  void _addMember() =>
      context.push('${AppRoutes.members}/new?gymId=${widget.gym.gymId}');

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(memberOverviewQueryProvider);
    final state = ref.watch(memberOverviewProvider(query));
    if (state.asData?.value case final page?) _last = page;
    final page = state.asData?.value;
    final counts = (page ?? _last)?.counts;
    final gymName = currentOwnerProfile(ref)?.gymName ?? '';
    final searching = query.search.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppSurfaces.of(context).canvasGradient,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth > AppSpacing.contentWidth
              ? (constraints.maxWidth - AppSpacing.contentWidth) / 2 +
                    AppSpacing.lg
              : AppSpacing.lg;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.lg,
                horizontal,
                AppSpacing.xl,
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Members',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    // Narrow screens or large text keep an icon-only button.
                    if (constraints.maxWidth < 360 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20)
                      IconButton.filled(
                        tooltip: 'Add member',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add_outlined),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Add member'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _search,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search members',
                    hintText: 'Name, phone or member code',
                    counterText: '',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              _applySearch();
                            },
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _applySearch(),
                  onChanged: (value) {
                    if (value.isEmpty && searching) _applySearch();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                OverviewFilterChips(
                  selected: query.filter,
                  counts: counts,
                  onSelected: (filter) => ref
                      .read(memberOverviewQueryProvider.notifier)
                      .select(filter),
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.isLoading && page == null)
                  const MembersFeedbackPanel(
                    loading: true,
                    title: 'Loading members',
                    child: Text(
                      'Getting your member list ready.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (state.hasError)
                  MembersFeedbackPanel(
                    icon: Icons.cloud_off_outlined,
                    title: 'Unable to load members',
                    child: MemberError(error: state.error, retry: _refresh),
                  )
                else if (page != null) ...[
                  if (page.rows.isEmpty)
                    _EmptyMembers(
                      query: query,
                      totalMembers: page.counts[MemberOverviewFilter.all],
                      addMember: _addMember,
                      showAll: () {
                        _search.clear();
                        ref
                            .read(memberOverviewQueryProvider.notifier)
                            .select(MemberOverviewFilter.all);
                        _applySearch();
                      },
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        _summary(query, page),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    MemberOverviewList(
                      children: [
                        for (final row in page.rows)
                          MemberOverviewTile(
                            row: row,
                            gym: widget.gym,
                            gymName: gymName,
                            showVisits:
                                query.filter == MemberOverviewFilter.inactive,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  PageControls(
                    page: page.pagination.page,
                    total: page.pagination.total,
                    previous: page.pagination.hasPrevious
                        ? () => ref
                              .read(memberOverviewQueryProvider.notifier)
                              .page(query.page - 1)
                        : null,
                    next: page.pagination.hasNext
                        ? () => ref
                              .read(memberOverviewQueryProvider.notifier)
                              .page(query.page + 1)
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _summary(MemberOverviewQuery query, MemberOverviewPage page) {
    final total = page.pagination.total;
    final noun = total == 1 ? 'member' : 'members';
    return switch (query.filter) {
      MemberOverviewFilter.all => '$total $noun',
      MemberOverviewFilter.active => '$total with an active membership',
      MemberOverviewFilter.expiring => '$total expiring in the next 7 days',
      MemberOverviewFilter.dues => '$total $noun owe money',
      MemberOverviewFilter.expired => '$total expired, not renewed',
      MemberOverviewFilter.none => '$total without a membership',
      MemberOverviewFilter.inactive => '$total not visited in 10+ days',
    };
  }
}

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers({
    required this.query,
    required this.totalMembers,
    required this.addMember,
    required this.showAll,
  });
  final MemberOverviewQuery query;
  final int totalMembers;
  final VoidCallback addMember, showAll;
  @override
  Widget build(BuildContext context) {
    if (totalMembers == 0) {
      return MembersFeedbackPanel(
        icon: Icons.people_outline,
        title: 'Add your first member',
        child: Column(
          children: [
            const Text(
              'Members you add appear here with their plan, days left and dues.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: addMember, child: const Text('Add member')),
          ],
        ),
      );
    }
    final message = query.search.isNotEmpty
        ? 'No members match “${query.search}”.'
        : switch (query.filter) {
            MemberOverviewFilter.expiring =>
              'No memberships end in the next 7 days.',
            MemberOverviewFilter.dues => 'Nobody owes money right now.',
            MemberOverviewFilter.expired => 'No expired memberships to renew.',
            MemberOverviewFilter.none => 'Every member has a membership.',
            MemberOverviewFilter.inactive =>
              'Every active member visited in the last 10 days.',
            _ => 'No members to show.',
          };
    return MembersFeedbackPanel(
      icon: Icons.check_circle_outline,
      title: 'All clear',
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: showAll,
            child: const Text('Show all members'),
          ),
        ],
      ),
    );
  }
}
