import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/page_controls.dart';
import 'lead_widgets.dart';
import 'leads.dart';
import '../../shared/widgets/page_section.dart';

/// Enquiries: who to follow up today, the pipeline, and top referrers.
class LeadsPage extends ConsumerStatefulWidget {
  const LeadsPage({super.key});
  @override
  ConsumerState<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends ConsumerState<LeadsPage> {
  final _search = TextEditingController();
  LeadPage? _last;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final leadId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddLeadSheet(),
    );
    ref.invalidate(leadsProvider);
    if (leadId != null && mounted) context.push('${AppRoutes.leads}/$leadId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(leadQueryProvider);
    final state = ref.watch(leadsProvider(query));
    if (state.asData?.value case final page?) _last = page;
    final page = state.asData?.value;
    final counts = _last;
    final referrers = ref.watch(referralsProvider).asData?.value;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add enquiry'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leadsProvider);
          ref.invalidate(referralsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            120,
          ),
          children: [
            Text('Enquiries', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'People interested in joining. Follow up, offer a 3-day trial, and convert them to members.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search enquiries',
                hintText: 'Name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          ref.read(leadQueryProvider.notifier).search('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
              onSubmitted: (value) =>
                  ref.read(leadQueryProvider.notifier).search(value),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in LeadFilter.values) ...[
                    ChoiceChip(
                      label: Text(
                        counts == null
                            ? filter.label
                            : '${filter.label} ${counts.count(filter)}',
                      ),
                      selected: filter == query.filter,
                      labelStyle: TextStyle(
                        color: filter == query.filter
                            ? AppPalette.onAccent
                            : filter == LeadFilter.due
                            ? AppPalette.amber
                            : null,
                      ),
                      onSelected: (_) =>
                          ref.read(leadQueryProvider.notifier).select(filter),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (state.isLoading && page == null)
              const Center(child: CircularProgressIndicator())
            else if (state.hasError)
              Column(
                children: [
                  Text(
                    state.error is LeadFailure
                        ? (state.error! as LeadFailure).message
                        : 'Enquiries could not be loaded.',
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(leadsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (page != null) ...[
              if (page.leads.isEmpty)
                PlainBlock(
                  child: Text(
                    query.filter == LeadFilter.due
                        ? 'No follow-ups due. Nice work.'
                        : 'No enquiries here yet. Tap Add enquiry when someone asks about joining.',
                  ),
                )
              else
                for (final lead in page.leads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: LeadTile(lead: lead),
                  ),
              PageControls(
                page: page.pagination.page,
                total: page.pagination.total,
                previous: page.pagination.hasPrevious
                    ? () => ref
                          .read(leadQueryProvider.notifier)
                          .page(query.page - 1)
                    : null,
                next: page.pagination.hasNext
                    ? () => ref
                          .read(leadQueryProvider.notifier)
                          .page(query.page + 1)
                    : null,
              ),
            ],
            if (referrers != null && referrers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Top referrers', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              PlainBlock(
                child: Column(
                  children: [
                    for (final row in referrers.take(5))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events_outlined, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(row.member.name)),
                            Text(
                              '${row.joined} joined of ${row.referred}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
