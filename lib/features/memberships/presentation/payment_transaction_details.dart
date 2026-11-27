import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/formatting/payment_date.dart';
import '../models/billing_models.dart';

/// Genuine saved transaction information; no invented receipt identifiers.
class PaymentTransactionDetails extends StatelessWidget {
  const PaymentTransactionDetails({
    super.key,
    required this.payment,
    this.timezone,
  });
  final RecordedPayment payment;
  final String? timezone;

  @override
  Widget build(BuildContext context) {
    final status = switch (payment.status) {
      'succeeded' => 'Successful payment',
      'pending' => 'Pending payment',
      'failed' => 'Failed payment',
      'cancelled' => 'Cancelled payment',
      _ => 'Payment status unavailable',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatInrPaise(payment.amountPaise),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFamily: AppTypography.bodyFamily,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppSurfaces.of(context).accent(
              payment.status == 'succeeded'
                  ? AppTone.positive
                  : AppTone.expired,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppSurfaces.of(context).onAccent(
                payment.status == 'succeeded'
                    ? AppTone.positive
                    : AppTone.expired,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IconLabel(
          'Payment method: ${payment.method.label}',
          icon: Icons.account_balance_wallet_outlined,
        ),
        IconLabel(
          'Paid: ${formatPaymentDateTime(MaterialLocalizations.of(context), payment.paidAt, timezone: timezone)}',
          icon: Icons.event_available_outlined,
        ),
        if (payment.reference case final reference?) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('Transaction reference'),
          SelectableText(reference),
        ],
      ],
    );
  }
}

/// A payment as one list row: amount, how and when, and its receipt.
class PaymentRow extends StatelessWidget {
  const PaymentRow({
    super.key,
    required this.payment,
    this.timezone,
    this.onTap,
    this.onReceipt,
  });
  final RecordedPayment payment;
  final String? timezone;
  final VoidCallback? onTap, onReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = payment.status != 'succeeded';
    final when = formatPaymentDateTime(
      MaterialLocalizations.of(context),
      payment.paidAt,
      timezone: timezone,
      showZone: false,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        failed ? Icons.error_outline : Icons.check_circle_outline,
        color: failed ? AppPalette.accentLight : null,
      ),
      title: Text(
        formatInrPaise(payment.amountPaise),
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      subtitle: Text(
        [
          payment.method.label,
          when,
          if (payment.isOpeningBalance) 'Paid before app',
          if (failed) payment.status,
          if (payment.reference case final reference?) 'Ref $reference',
        ].join(' · '),
      ),
      trailing: onReceipt == null
          ? null
          : IconButton(
              tooltip: 'Share receipt',
              onPressed: onReceipt,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
    );
  }
}
