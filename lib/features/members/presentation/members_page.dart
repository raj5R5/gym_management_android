import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/member_failure.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import 'member_list_widgets.dart';
import '../../memberships/data/outstanding_dues_repository.dart';
import '../../memberships/models/membership_eligibility.dart';

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
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(memberQueryProvider).search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void>? _refreshFlight;
  Future<void> _refresh() {
    final pending = _refreshFlight;
    if (pending != null) return pending;
    late final Future<void> flight;
    flight = _reloadDirectory().whenComplete(() {
      if (identical(_refreshFlight, flight)) _refreshFlight = null;
    });
    return _refreshFlight = flight;
  }

  Future<void> _reloadDirectory() async {
    try {
      await ref.read(membersProvider.notifier).reload();
      if (!mounted || ref.read(adminGymProvider) != widget.gym) return;
      for (final member
          in ref.read(membersProvider).asData?.value?.members ??
              <MemberProfile>[]) {
        final scope = scopeFor(widget.gym, member.id);
        ref.invalidate(memberMembershipsProvider(scope));
      }
    } on MemberFailure {
      /* AsyncValue renders the safe failure. */
    }
  }

  void _apply(String? gender) => ref
      .read(memberQueryProvider.notifier)
      .apply(search: _search.text, gender: gender);
  void _addMember() =>
      context.push('${AppRoutes.members}/new?gymId=${widget.gym.gymId}');

  Widget _header() => Row(
    children: [
      Expanded(
        child: Text(
          'Members',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      IconButton.filled(
        tooltip: 'Add member',
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          minimumSize: const Size(48, 48),
        ),
        onPressed: _addMember,
        icon: const Icon(Icons.person_add_outlined),
      ),
    ],
  );

  Widget _filters(MemberListQuery query) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _search,
          maxLength: 100,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search members',
            hintText: 'Code, name or phone',
            counterText: '',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: () => _apply(query.gender),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (_) => _apply(query.gender),
          onChanged: (value) {
            if (value.isEmpty && query.search.isNotEmpty) _apply(query.gender);
          },
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      PopupMenuButton<String>(
        tooltip: 'Filter by gender',
        initialValue: query.gender ?? '',
        onSelected: (value) => _apply(value.isEmpty ? null : value),
        icon: Badge(
          isLabelVisible: query.gender != null,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.filter_list),
        ),
        itemBuilder: (_) => [
          for (final option in [
            ('', 'All'),
            ('male', 'Male'),
            ('female', 'Female'),
          ])
            CheckedPopupMenuItem(
              value: option.$1,
              checked: (query.gender ?? '') == option.$1,
              child: Text(option.$2),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(membersProvider);
    final query = ref.watch(memberQueryProvider);
    final result = state.asData?.value;
    final filtered = query.search.isNotEmpty || query.gender != null;
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
                _header(),
                const SizedBox(height: AppSpacing.xl),
                _filters(query),
                const SizedBox(height: AppSpacing.xl),
                if (state.isLoading)
                  const MembersFeedbackPanel(
                    loading: true,
                    title: 'Loading members',
                    child: Text(
                      'Getting your member directory ready.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (state.hasError)
                  MembersFeedbackPanel(
                    icon: Icons.cloud_off_outlined,
                    title: 'Unable to load members',
                    child: MemberError(error: state.error, retry: _refresh),
                  )
                else if (result != null) ...[
                  if (result.members.isEmpty)
                    MembersFeedbackPanel(
                      icon: filtered ? Icons.search_off : Icons.people_outline,
                      title: filtered || query.page > 1
                          ? 'No matching members'
                          : 'Your community starts here',
                      child: Column(
                        children: [
                          Text(
                            !filtered && query.page == 1
                                ? 'No members yet. Add your first member.'
                                : 'No members match this page or filter.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (!filtered && query.page == 1)
                            FilledButton(
                              onPressed: _addMember,
                              child: const Text('Create your first member'),
                            )
                          else
                            OutlinedButton(
                              onPressed: () {
                                _search.clear();
                                _apply(null);
                              },
                              child: Text(
                                filtered
                                    ? 'Clear filters'
                                    : 'Return to first page',
                              ),
                            ),
                        ],
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        '${result.pagination.total} ${filtered ? 'matching members' : 'members'}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    ResponsiveMemberGrid(
                      children: [
                        for (final member in result.members)
                          _DirectoryCard(gym: widget.gym, member: member),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  PageControls(
                    page: result.pagination.page,
                    total: result.pagination.total,
                    previous: result.pagination.hasPrevious
                        ? () => ref
                              .read(memberQueryProvider.notifier)
                              .page(query.page - 1)
                        : null,
                    next: result.pagination.hasNext
                        ? () => ref
                              .read(memberQueryProvider.notifier)
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
}

class _DirectoryCard extends ConsumerWidget {
  const _DirectoryCard({required this.gym, required this.member});
  final AdminGymContext gym;
  final MemberProfile member;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = scopeFor(gym, member.id);
    final memberships = ref.watch(memberMembershipsProvider(scope));
    AsyncValue<int?> dues;
    if (memberships.isLoading) {
      dues = const AsyncLoading();
    } else if (memberships.hasError) {
      dues = AsyncError(
        memberships.error!,
        memberships.stackTrace ?? StackTrace.current,
      );
    } else if (memberships.asData?.value case final records?) {
      try {
        dues = AsyncData(
          OutstandingDues([
            OutstandingMember(member, verifiedUnpaidMemberships(records)),
          ]).totalPaise,
        );
      } catch (error, stack) {
        dues = AsyncError(error, stack);
      }
    } else {
      dues = const AsyncData(null);
    }
    return MemberDirectoryCard(
      member: member,
      memberships: memberships,
      outstandingDues: dues,
      retry: () {
        ref.invalidate(memberMembershipsProvider(scope));
      },
      onTap: () => context.push(memberPath(scope)),
    );
  }
}
