import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../models/onboarding_wizard_state.dart';
import 'onboarding_payment_step.dart';

const onboardingConfirmationMessage =
    'Confirm saves the member, their plan and payment together.';

class OnboardingReviewStep extends StatelessWidget {
  const OnboardingReviewStep({
    super.key,
    required this.draft,
    required this.gymId,
    required this.onEdit,
  });
  final OnboardingWizardState draft;
  final String gymId;
  final ValueChanged<OnboardingWizardStep> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = draft.reviewIssues(gymId: gymId);
    final member = draft.memberDetailsValid
        ? draft.toMemberDraft().toJson(editing: false)
        : null;
    final plan = draft.selectedPlan;
    final memberOnly = draft.registerMemberOnly;
    final withPayment =
        !memberOnly &&
        draft.paymentValid &&
        (draft.initialPaymentPaise ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReviewSection(
          title: memberOnly
              ? 'Member registration only'
              : withPayment
              ? 'Member + membership + initial payment'
              : 'Member + membership',
          icon: Icons.fact_check_outlined,
          child: Text(
            memberOnly
                ? 'Member-only registration · No membership or payment'
                : withPayment
                ? 'Review the member, plan and initial payment below.'
                : draft.paymentValid
                ? 'No initial payment will be recorded.'
                : 'Check the membership and payment details below.',
          ),
        ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: true,
            child: _ReviewSection(
              title: 'Fix these details before registration',
              icon: Icons.error_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final issue in issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(issue.message),
                          TextButton(
                            onPressed: () => onEdit(issue.step),
                            child: Text('Fix ${issue.step.title}'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ReviewSection(
          title: 'Member details',
          icon: Icons.person_outline,
          editLabel: 'Edit member details',
          onEdit: () => onEdit(OnboardingWizardStep.memberDetails),
          child: member == null
              ? const Text(
                  'Complete or correct the member details to review them.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${member['firstName']} ${member['lastName']}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    IconLabel(
                      'Member code: ${member['memberCode']}',
                      icon: Icons.badge_outlined,
                    ),
                    IconLabel(
                      'Phone: ${member['phone']}',
                      icon: Icons.phone_outlined,
                    ),
                    if (member['dateOfBirth'] != null)
                      IconLabel(
                        'Date of birth: ${member['dateOfBirth']}',
                        icon: Icons.cake_outlined,
                      ),
                    if (member['gender'] != null)
                      IconLabel(
                        'Gender: ${(member['gender'] as String).replaceAll('_', ' ')}',
                        icon: Icons.person_outline,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (memberOnly)
          _ReviewSection(
            title: 'Membership',
            icon: Icons.fitness_center,
            editLabel: 'Edit membership selection',
            onEdit: () => onEdit(OnboardingWizardStep.membershipPlan),
            child: const Text(
              'No membership selected. A membership can be purchased later.',
            ),
          )
        else ...[
          _ReviewSection(
            title: 'Membership',
            icon: Icons.fitness_center,
            editLabel: 'Edit membership selection',
            onEdit: () => onEdit(OnboardingWizardStep.membershipPlan),
            child: plan == null
                ? const Text('No membership plan selected.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Membership plan: ${plan.name}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${plan.durationDays} days · ${formatInrPaise(plan.pricePaise)}',
                      ),
                      if (plan.pricePaise == 0)
                        Text(
                          'Free plan · ${formatInrPaise(plan.pricePaise)}. No payment is due.',
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      if (draft.existingMember && draft.joinedOnDate != null)
                        IconLabel(
                          'Existing member · plan started ${MaterialLocalizations.of(context).formatMediumDate(draft.joinedOnDate!.value)}',
                          icon: Icons.history_outlined,
                        )
                      else
                        const IconLabel(
                          'Start date: Set by the backend when saved (gym timezone).',
                          icon: Icons.event_available_outlined,
                        ),
                    ],
                  ),
          ),
          if (plan != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _ReviewSection(
              title: withPayment
                  ? 'Initial payment & balance'
                  : 'Payment & balance',
              icon: Icons.account_balance_wallet_outlined,
              editLabel: 'Edit initial payment',
              onEdit: () => onEdit(OnboardingWizardStep.payment),
              child: OnboardingPaymentSummary(draft: draft),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.xl),
        const Text(onboardingConfirmationMessage),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.child,
    this.editLabel,
    this.onEdit,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final String? editLabel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: AppSurfaces.of(context).border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
            if (onEdit != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(editLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
