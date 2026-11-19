import '../../../shared/widgets/field_icon.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../memberships/models/billing_models.dart';
import '../models/onboarding_wizard_state.dart';

class OnboardingPaymentStep extends StatelessWidget {
  const OnboardingPaymentStep({
    super.key,
    required this.draft,
    required this.formKey,
    required this.onChanged,
  });
  final OnboardingWizardState draft;
  final GlobalKey<FormState> formKey;
  final ValueChanged<OnboardingWizardState> onChanged;

  @override
  Widget build(BuildContext context) {
    final plan = draft.selectedPlan;
    if (plan == null) {
      return const Text('Select a membership plan before entering payment.');
    }
    final positive = (draft.initialPaymentPaise ?? 0) > 0;
    final requiredReference =
        positive && (draft.paymentMethod?.requiresReference ?? false);
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Selected plan: ${plan.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (plan.pricePaise == 0)
            Text(
              'Free plan · ${formatInrPaise(plan.pricePaise)}. No initial payment is required.',
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Skip initial payment'),
              subtitle: const Text(
                'Register the membership without an initial payment.',
              ),
              value: draft.skipInitialPayment,
              onChanged: (skip) =>
                  onChanged(draft.copyWith(skipInitialPayment: skip)),
            ),
            if (draft.skipInitialPayment)
              const Text(
                'No initial payment. The full plan price remains outstanding.',
              )
            else ...[
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const ValueKey('initialPaymentAmount'),
                initialValue: draft.paymentAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('amount'),
                  labelText: 'Initial payment amount (INR)',
                  prefixText: '₹ ',
                  helperText:
                      'Enter rupees, e.g. 500.50. Zero records no payment.',
                ),
                onChanged: (amount) =>
                    onChanged(draft.copyWith(paymentAmount: amount)),
                validator: (_) => draft.paymentAmountError,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<PaymentMethod>(
                itemHeight: null,
                key: const ValueKey('initialPaymentMethod'),
                isExpanded: true,
                initialValue: draft.paymentMethod,
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('method'),
                  labelText: 'Payment method',
                ),
                items: [
                  for (final method in PaymentMethod.values)
                    DropdownMenuItem(
                      value: method,
                      child: Text(
                        method.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (method) {
                  if (method != null) {
                    onChanged(draft.copyWith(paymentMethod: method));
                  }
                },
                validator: (method) => positive && method == null
                    ? 'Select a payment method.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                key: const ValueKey('initialPaymentReference'),
                initialValue: draft.paymentReference,
                maxLength: 120,
                decoration: InputDecoration(
                  prefixIcon: const FieldIcon('reference'),
                  labelText: requiredReference
                      ? 'Payment reference (required)'
                      : 'Payment reference (optional)',
                  helperText:
                      'Transaction reference only. Never enter card or banking credentials.',
                ),
                onChanged: (reference) =>
                    onChanged(draft.copyWith(paymentReference: reference)),
                validator: (_) => draft.initialPaymentReferenceError,
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          OnboardingPaymentSummary(draft: draft),
          const SizedBox(height: AppSpacing.md),
          const Text('Preview only. Nothing has been saved or recorded.'),
        ],
      ),
    );
  }
}

class OnboardingPaymentSummary extends StatelessWidget {
  const OnboardingPaymentSummary({super.key, required this.draft});
  final OnboardingWizardState draft;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final amount = draft.initialPaymentPaise;
    final balance = draft.remainingBalancePaise;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.inactive,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: surfaces.onStatus),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plan price: ${formatInrPaise(draft.selectedPlan?.pricePaise ?? 0)}',
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Initial payment: ${amount == null ? 'Enter a valid amount' : formatInrPaise(amount)}',
              ),
              if ((amount ?? 0) > 0 && draft.paymentMethod != null) ...[
                Text('Payment method: ${draft.paymentMethod!.label}'),
                if (draft.paymentReference.trim().isNotEmpty)
                  Text('Reference: ${draft.paymentReference.trim()}'),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Remaining balance: ${balance == null ? 'Enter a valid amount' : formatInrPaise(balance)}',
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Remaining balance = plan price − initial payment.'),
            ],
          ),
        ),
      ),
    );
  }
}
