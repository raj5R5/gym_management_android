import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/member_failure.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';

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

  Future<void> _refresh() async {
    try {
      await ref.read(membersProvider.notifier).reload();
    } on MemberFailure {
      /* AsyncValue renders the safe failure. */
    }
  }

  void _apply(MemberStatus? status) => ref
      .read(memberQueryProvider.notifier)
      .apply(search: _search.text, status: status);
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(membersProvider);
    final query = ref.watch(memberQueryProvider);
    final result = state.asData?.value;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                'Members',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.members}/new?gymId=${widget.gym.gymId}',
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add member'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search members',
              hintText: 'Code, name or phone',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: () => _apply(query.status),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _apply(query.status),
            onChanged: (value) {
              if (value.isEmpty && query.search.isNotEmpty) {
                _apply(query.status);
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<MemberStatus?>(
            isExpanded: true,
            key: ValueKey(query.status),
            initialValue: query.status,
            decoration: const InputDecoration(labelText: 'Member status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              ...MemberStatus.values.map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status.name)),
              ),
            ],
            onChanged: _apply,
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading members',
              ),
            )
          else if (state.hasError)
            MemberError(error: state.error, retry: _refresh)
          else if (result != null) ...[
            if (result.members.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  query.search.isEmpty &&
                          query.status == null &&
                          query.page == 1
                      ? 'No members yet. Add your first member.'
                      : 'No members match this page or filter.',
                ),
              ),
            ...result.members.map(
              (member) => Card(
                child: ListTile(
                  isThreeLine: true,
                  title: Text(member.name),
                  subtitle: Text(
                    '${member.memberCode} · ${member.phone}\n${member.status.name}${member.branchId == null ? ' · No branch assigned' : ' · Branch: ${member.branchId}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push(memberPath(scopeFor(widget.gym, member.id))),
                ),
              ),
            ),
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
  }
}
