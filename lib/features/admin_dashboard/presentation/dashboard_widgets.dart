import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../models/dashboard_models.dart';
import '../../../shared/widgets/page_section.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.period,
    required this.filter,
    required this.selectPeriod,
    required this.selectPreset,
    required this.refresh,
    this.timezone,
  });
  final String period;
  final String? timezone;
  final DashboardDateFilter filter;
  final VoidCallback selectPeriod;
  final ValueChanged<DashboardDateFilter> selectPreset;
  final VoidCallback? refresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: const Key('dashboard-period'),
      label:
          'Revenue dates: $period${timezone == null ? '' : '. Gym timezone: $timezone'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in const {
                  DashboardDateFilter.today: 'Today',
                  DashboardDateFilter.last7Days: '7 days',
                  DashboardDateFilter.thisMonth: 'This month',
                  DashboardDateFilter.customRange: 'Custom range',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    labelPadding: EdgeInsets.zero,
                    selected: filter == entry.key,
                    showCheckmark: false,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: filter == entry.key
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                    onSelected: (_) =>
                        entry.key == DashboardDateFilter.customRange
                        ? selectPeriod()
                        : selectPreset(entry.key),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: refresh,
            icon: const Icon(Icons.refresh, size: 22),
          ),
        ],
      ),
    );
  }
}

/// A current status distribution, never a trend or a selected-period metric.
class ProfileStatusSummary extends StatelessWidget {
  const ProfileStatusSummary({super.key, required this.metrics});
  final ProfileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final segments = [
      (count: metrics.active, color: surfaces.active),
      (count: metrics.inactive, color: surfaces.inactive),
      (count: metrics.suspended, color: surfaces.suspended),
    ];
    if (segments.every((segment) => segment.count == 0)) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label:
          'Current status distribution: ${metrics.active} active, ${metrics.inactive} inactive, ${metrics.suspended} suspended',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: SizedBox(
            height: AppSpacing.sm,
            child: Row(
              children: [
                for (final segment in segments)
                  if (segment.count > 0)
                    Expanded(
                      flex: segment.count,
                      child: ColoredBox(color: segment.color),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Current membership lifecycle, separate from account status or plan count.
class DashboardMembershipWatch extends StatelessWidget {
  const DashboardMembershipWatch({super.key, required this.metrics});
  final SubscriptionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    final values = [
      (
        'Active memberships',
        metrics.currentlyActive,
        surfaces.onAccent(AppTone.positive),
      ),
      (
        'Expiring soon',
        metrics.expiringSoon,
        PendingColors.accentFor(theme.brightness),
      ),
      (
        'Expired memberships',
        metrics.expired,
        theme.colorScheme.onSurfaceVariant,
      ),
    ];
    return SoftPanel(
      glass: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Membership overview', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 18.2
                  ? 3
                  : 1;
              final width =
                  (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final (label, count, color) in values)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        label: '$label: $count',
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$count',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(label, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class DashboardFeedbackPanel extends StatelessWidget {
  const DashboardFeedbackPanel({
    super.key,
    required this.title,
    required this.message,
    this.loading = false,
    this.icon = Icons.insights_outlined,
    this.action,
  });
  final String title, message;
  final bool loading;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SoftPanel(
    child: Column(
      children: [
        if (loading)
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              semanticsLabel: 'Loading dashboard',
            ),
          )
        else
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: !loading,
          child: Text(message, textAlign: TextAlign.center),
        ),
        if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
      ],
    ),
  );
}

class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({
    super.key,
    required this.checkIn,
    required this.addMember,
    required this.collectDues,
    required this.renewals,
    required this.viewPlans,
  });
  final VoidCallback checkIn, addMember, collectDues, renewals, viewPlans;

  @override
  Widget build(BuildContext context) => PlainBlock(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: checkIn,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Check in'),
            ),
            OutlinedButton.icon(
              onPressed: addMember,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add member'),
            ),
            OutlinedButton.icon(
              onPressed: collectDues,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Collect dues'),
            ),
            OutlinedButton.icon(
              onPressed: renewals,
              icon: const Icon(Icons.autorenew),
              label: const Text('Renewals'),
            ),
            TextButton.icon(
              onPressed: viewPlans,
              icon: const Icon(Icons.card_membership_outlined),
              label: const Text('Plans'),
            ),
          ],
        ),
      ],
    ),
  );
}
