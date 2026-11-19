import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../../shared/widgets/titanium_surface.dart';
import '../../members/presentation/member_list_widgets.dart' show StatusPill;
import '../models/billing_models.dart';

/// Plain words for a saved day count: "1 month", "3 months", "1 year", "45 days".
/// Months are 30-day blocks, years 365 days; the saved days stay authoritative.
String planDurationWords(int days) {
  String plural(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'}';
  if (days % 365 == 0) return plural(days ~/ 365, 'year');
  if (days % 30 == 0) return plural(days ~/ 30, 'month');
  if (days % 7 == 0) return plural(days ~/ 7, 'week');
  return plural(days, 'day');
}

/// Rounded price per day in paise.
int perDayPaise(MembershipPlan plan) =>
    (plan.pricePaise / plan.durationDays).round();

/// The shortest active, paid plan: what other plans are compared against.
MembershipPlan? comparisonBaseline(Iterable<MembershipPlan> plans) {
  MembershipPlan? baseline;
  for (final plan in plans) {
    if (plan.status != 'active' || plan.pricePaise == 0) continue;
    if (baseline == null || plan.durationDays < baseline.durationDays) {
      baseline = plan;
    }
  }
  return baseline;
}

/// Saving versus buying the baseline repeatedly for the same days, in whole rupees.
int savingsPaise(MembershipPlan plan, MembershipPlan? baseline) {
  if (baseline == null ||
      baseline.id == plan.id ||
      plan.durationDays <= baseline.durationDays) {
    return 0;
  }
  final equivalent =
      (baseline.pricePaise * plan.durationDays / baseline.durationDays).round();
  final saving = equivalent - plan.pricePaise;
  return saving >= 100 ? saving ~/ 100 * 100 : 0;
}

class PlanSummaryCard extends StatelessWidget {
  const PlanSummaryCard({
    super.key,
    required this.plan,
    required this.onEdit,
    this.baseline,
  });
  final MembershipPlan plan;
  final VoidCallback onEdit;

  /// Plan used for "saves ₹X vs …"; usually the shortest active plan.
  final MembershipPlan? baseline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = plan.status == 'active';
    final saving = savingsPaise(plan, baseline);
    final perDay = perDayPaise(plan);
    final members = plan.activeMemberCount;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SoftPanel(
        glass: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(plan.name, style: theme.textTheme.titleLarge),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  label: 'Plan status',
                  child: StatusPill(
                    label: active ? 'Active' : 'Inactive',
                    tone: active ? AppTone.positive : AppTone.expired,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              plan.pricePaise == 0
                  ? 'Free'
                  : formatCompactInrPaise(plan.pricePaise),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'for ${planDurationWords(plan.durationDays)}'
              '${planDurationWords(plan.durationDays).endsWith('days') ? '' : ' (${plan.durationDays} days)'}'
              '${plan.pricePaise == 0 ? '' : ' · ${formatCompactInrPaise(perDay)} per day'}',
              style: muted,
            ),
            if (saving > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Saves ${formatCompactInrPaise(saving)} vs ${baseline!.name}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (plan.description case final description?
                when description.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            const Divider(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final count = Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        members == null
                            ? 'Member count unavailable'
                            : members == 0
                            ? 'No members on this plan yet'
                            : '$members ${members == 1 ? 'member' : 'members'} on this plan',
                        style: muted,
                      ),
                    ),
                  ],
                );
                final edit = TitaniumPress(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit plan'),
                  ),
                );
                // Narrow screens or large text: stack instead of squeezing.
                final stacked =
                    constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22;
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          count,
                          const SizedBox(height: AppSpacing.sm),
                          edit,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: count),
                          const SizedBox(width: AppSpacing.sm),
                          edit,
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
