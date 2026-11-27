import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../members/presentation/member_list_widgets.dart';
import '../../members/providers/member_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/photos/member_photo_widgets.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import '../data/outstanding_dues_repository.dart';
import '../../../shared/widgets/page_section.dart';

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
          Text(
            'Everyone who owes money now, whatever the dashboard period.',
            style: Theme.of(context).textTheme.bodySmall,
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
          // One tap sorts; both choices stay visible.
          Row(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('Highest due'),
                selected: _highestFirst,
                onSelected: (_) => setState(() => _highestFirst = true),
              ),
              ChoiceChip(
                label: const Text('Name A–Z'),
                selected: !_highestFirst,
                onSelected: (_) => setState(() => _highestFirst = false),
              ),
            ],
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
            SeparatedRows(
              indent: 56,
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
      style: theme.textTheme.headlineMedium?.copyWith(
        fontFamily: AppTypography.bodyFamily,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return SoftPanel(
      key: const ValueKey('dues-summary'),
      glass: true,
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

/// A member who owes money, as one row: who, how much, and the plan.
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
    final dates = MaterialLocalizations.of(context);
    final membership = _displayedMembership;
    final count = row.memberships.length;
    final membershipCount =
        '$count unpaid ${count == 1 ? 'membership' : 'memberships'}';
    final plan = membership == null
        ? 'Membership dates unavailable'
        : membership.status == 'expired'
        ? '${membership.planName} · expired ${dates.formatShortMonthDay(membership.endDate.value)}'
        : membership.currentlyActive
        ? '${membership.planName} · ends ${dates.formatShortMonthDay(membership.endDate.value)}'
        : '${membership.planName} · ${membershipStatusLabel(membership)}';
    return Semantics(
      button: true,
      label:
          'View profile for ${row.member.name}. Member code: ${row.member.memberCode}. Total dues across $membershipCount.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              MemberPhotoAvatar(member: row.member, radius: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      plan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: membership?.status == 'expired'
                            ? AppPalette.accentLight
                            : null,
                      ),
                    ),
                    if (count > 1)
                      Text(
                        'Total across $membershipCount',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatCompactInrPaise(row.balancePaise),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PendingColors.accentFor(theme.brightness),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
