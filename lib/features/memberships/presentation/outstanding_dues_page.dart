import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../members/presentation/member_list_widgets.dart';
import '../../members/providers/member_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/photos/member_photo_widgets.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import '../data/outstanding_dues_repository.dart';

class OutstandingDuesPage extends ConsumerStatefulWidget {
  const OutstandingDuesPage({super.key, required this.gymId});
  final String? gymId;
  @override
  ConsumerState<OutstandingDuesPage> createState() =>
      _OutstandingDuesPageState();
}

class _OutstandingDuesPageState extends ConsumerState<OutstandingDuesPage> {
  final _search = TextEditingController();
  bool _highestFirst = true;
  AdminGymContext? _gym;
  OutstandingDues? _snapshot;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    if (_gym != gym) {
      _gym = gym;
      _search.clear();
      _highestFirst = true;
      _snapshot = null;
    }
    final dues = ref.watch(outstandingDuesProvider);
    if (!dues.isLoading && !dues.hasError) _snapshot = dues.asData?.value;
    final data = _snapshot;
    final verified = !dues.isLoading && !dues.hasError;
    Future<void> refresh() async {
      if (ref.read(outstandingDuesProvider).isLoading) return;
      ref.invalidate(outstandingDuesProvider);
      ref.invalidate(dashboardProvider);
      await ref
          .read(outstandingDuesProvider.future)
          .then<void>((_) {}, onError: (Object _) {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to dashboard',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.dashboard),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Outstanding Dues',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh dues',
                onPressed: dues.isLoading ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Text(
            'Current unpaid membership balances · All branches\nIndependent of the selected revenue period.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (data != null) ...[
            _DuesSummary(totalPaise: data.totalPaise, verified: verified),
            const SizedBox(height: AppSpacing.xl),
          ],
          TextField(
            controller: _search,
            maxLength: 100,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search members',
              hintText: 'Name, phone, code or plan',
              prefixIcon: Icon(Icons.search),
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<bool>(
            initialValue: _highestFirst,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Sort members'),
            items: const [
              DropdownMenuItem(
                value: true,
                child: Text('Highest balance first'),
              ),
              DropdownMenuItem(value: false, child: Text('Name A–Z')),
            ],
            onChanged: (value) => setState(() => _highestFirst = value!),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (data != null && (dues.isLoading || dues.hasError))
            FinancialRefreshStatus(
              loading: dues.isLoading,
              error: dues.error,
              retry: refresh,
            ),
          if (dues.isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (dues.hasError && data == null)
            BillingError(
              error: dues.error,
              retry: () => ref.invalidate(outstandingDuesProvider),
            ),
          if (data != null) ...[
            if (data.members.isEmpty)
              Text(
                verified
                    ? 'No outstanding dues in the current list.'
                    : 'No outstanding dues in the last verified results.',
              )
            else if (data.search(_search.text).isEmpty)
              const Text('No members match your search.'),
            ResponsiveMemberGrid(
              children: [
                for (final row in data.search(
                  _search.text,
                  highestFirst: _highestFirst,
                ))
                  _OutstandingMemberCard(
                    key: ValueKey(row.member.id),
                    row: row,
                    onView: () =>
                        context.push(memberPath(scopeFor(gym, row.member.id))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DuesSummary extends StatelessWidget {
  const _DuesSummary({required this.totalPaise, required this.verified});
  final int totalPaise;
  final bool verified;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: PendingColors.accent,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: const Icon(
        Icons.account_balance_wallet_outlined,
        color: PendingColors.onAccent,
      ),
    );
    final label = Text(
      verified ? 'Total current dues' : 'Last verified dues',
      style: theme.textTheme.labelLarge,
    );
    final amount = Text(
      formatInrPaise(totalPaise),
      style: theme.textTheme.headlineMedium,
    );
    return SoftPanel(
      key: const ValueKey('dues-summary'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      backgroundColor: PendingColors.surfaceFor(theme.brightness),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText =
              MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
          if (constraints.maxWidth < 340 && largeText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: label),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                amount,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: AppSpacing.xs),
                    amount,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OutstandingMemberCard extends StatelessWidget {
  const _OutstandingMemberCard({
    super.key,
    required this.row,
    required this.onView,
  });
  final OutstandingMember row;
  final VoidCallback onView;

  Membership? get _displayedMembership {
    final ordered = row.memberships.toList()
      ..sort((a, b) {
        final current =
            (b.currentlyActive ? 1 : 0) - (a.currentlyActive ? 1 : 0);
        return current != 0 ? current : b.startDate.compareTo(a.startDate);
      });
    return ordered.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membership = _displayedMembership;
    final color = AppSurfaces.of(context).memberCard(
      membership?.status == 'expired'
          ? MemberCardTone.expired
          : MemberCardTone.due,
      theme.brightness,
    );
    return Semantics(
      button: true,
      label:
          'View profile for ${row.member.name}. Total dues across ${row.memberships.length} unpaid memberships.',
      child: Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onView,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MemberPhotoAvatar.cover(member: row.member, height: 168),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.member.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${formatCompactInrPaise(row.balancePaise)} due',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: PendingColors.accentFor(theme.brightness),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (membership == null)
                      const Text('Membership dates unavailable')
                    else ...[
                      MembershipDateRange(
                        start: membership.startDate.value,
                        end: membership.endDate.value,
                        previous: membership.status == 'expired',
                      ),
                      if (membership.status == 'expired') ...[
                        const SizedBox(height: AppSpacing.sm),
                        const StatusPill(
                          label: 'Expired',
                          tone: AppTone.expired,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
