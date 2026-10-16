import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../memberships/models/billing_models.dart';
import '../../memberships/presentation/billing_components.dart';

/// Presentation only; the wizard supplies the existing scoped provider's state.
class OnboardingPlanSelection extends StatelessWidget {
  const OnboardingPlanSelection({
    super.key,
    required this.plans,
    required this.selectedPlan,
    required this.onSelect,
    required this.retry,
    required this.onPage,
    this.onCreatePlan,
  });

  final AsyncValue<BillingPage<MembershipPlan>?> plans;
  final MembershipPlan? selectedPlan;
  final ValueChanged<MembershipPlan> onSelect;
  final VoidCallback retry;
  final ValueChanged<int> onPage;
  final VoidCallback? onCreatePlan;

  @override
  Widget build(BuildContext context) {
    final data = plans.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedPlan case final plan?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              'Selected plan: ${plan.name} · ${formatInrPaise(plan.pricePaise)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (plans.isLoading)
          const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpacing.md),
              Text('Loading membership plans…'),
            ],
          )
        else if (plans.hasError)
          BillingError(error: plans.error, retry: retry)
        else if (data == null)
          const Text(
            'Plans are unavailable for the current gym. Return to Members to continue.',
          )
        else ...[
          if (data.items.isEmpty) ...[
            const Text(
              'No active membership plans. Create a plan before assigning a membership, or choose Register member only.',
            ),
            if (onCreatePlan != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onCreatePlan,
                icon: const Icon(Icons.add),
                label: const Text('Create membership plan'),
              ),
            ],
          ] else ...[
            const Text('Select an active plan to continue.'),
            const SizedBox(height: AppSpacing.lg),
            for (final plan in data.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PlanCard(
                  plan: plan,
                  selected: selectedPlan?.id == plan.id,
                  onTap: () => onSelect(plan),
                ),
              ),
          ],
          if (data.pagination.hasPrevious || data.pagination.hasNext)
            PageControls(
              page: data.pagination.page,
              total: data.pagination.total,
              previous: data.pagination.hasPrevious
                  ? () => onPage(data.pagination.page - 1)
                  : null,
              next: data.pagination.hasNext
                  ? () => onPage(data.pagination.page + 1)
                  : null,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh plans'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });
  final MembershipPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    final foreground = selected
        ? surfaces.onStatus
        : theme.colorScheme.onSurface;
    final radius = BorderRadius.circular(AppRadii.card);
    return Semantics(
      selected: selected,
      child: Material(
        key: ValueKey('onboarding-plan-${plan.id}'),
        color: selected ? surfaces.active : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? surfaces.onStatus : surfaces.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: foreground,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  plan.pricePaise == 0
                      ? 'Free · ${formatInrPaise(0)}'
                      : formatInrPaise(plan.pricePaise),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: foreground,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${plan.durationDays} days',
                  style: TextStyle(color: foreground),
                ),
                if (plan.description case final description?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(description, style: TextStyle(color: foreground)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
