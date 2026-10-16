import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../models/dashboard_models.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
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
                selectedColor: theme.colorScheme.primaryContainer,
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: filter == entry.key
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
                onSelected: (_) => entry.key == DashboardDateFilter.customRange
                    ? selectPeriod()
                    : selectPreset(entry.key),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                period,
                key: const Key('dashboard-period'),
                style: theme.textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: refresh,
              icon: const Icon(Icons.refresh, size: 22),
            ),
          ],
        ),
        if (timezone != null) ...[
          Text(
            'Gym timezone: $timezone',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
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
    required this.addMember,
    required this.viewMembers,
    required this.viewTrainers,
    required this.viewPlans,
  });
  final VoidCallback addMember, viewMembers, viewTrainers, viewPlans;

  @override
  Widget build(BuildContext context) => SoftPanel(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: addMember,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add member'),
            ),
            TextButton.icon(
              onPressed: viewMembers,
              icon: const Icon(Icons.people_outline),
              label: const Text('View members'),
            ),
            TextButton.icon(
              onPressed: viewTrainers,
              icon: const Icon(Icons.fitness_center),
              label: const Text('View trainers'),
            ),
            TextButton.icon(
              onPressed: viewPlans,
              icon: const Icon(Icons.card_membership_outlined),
              label: const Text('Membership plans'),
            ),
          ],
        ),
      ],
    ),
  );
}
