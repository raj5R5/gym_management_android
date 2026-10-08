import 'package:flutter/material.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../members/data/member_failure.dart';
import '../../members/providers/member_providers.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/formatting/inr.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
export '../../../shared/widgets/profile_section.dart';
export '../../../shared/widgets/page_controls.dart';

String membershipPath(
  MemberScope scope, {
  bool purchase = false,
  String? subscriptionId,
}) =>
    '${AppRoutes.members}/${scope.memberId}/membership${purchase
        ? '/purchase'
        : subscriptionId == null
        ? ''
        : '/$subscriptionId'}?gymId=${Uri.encodeQueryComponent(scope.gymId)}';

class BillingError extends StatelessWidget {
  const BillingError({super.key, required this.error, this.retry});
  final Object? error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            error is BillingFailure
                ? (error as BillingFailure).message
                : error is MemberFailure
                ? (error as MemberFailure).message
                : 'Billing information could not be loaded. Please try again.',
          ),
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class BillingResultCard extends StatelessWidget {
  const BillingResultCard({super.key, required this.result});
  final BillingResult result;
  @override
  Widget build(BuildContext context) => ProfileSection(
    title: 'Server confirmation',
    children: [
      Text(result.subscription.planName),
      Text('Status: ${result.subscription.status}'),
      Text(
        '${result.subscription.startDate} → ${result.subscription.endDate} (end exclusive, UTC)',
      ),
      Text(
        'Plan snapshot: ${formatInrPaise(result.subscription.pricePaise)} · ${result.subscription.durationDays} days',
      ),
      if (result.payment case final RecordedPayment payment) ...[
        Text(
          'Successful payment: ${formatInrPaise(payment.amountPaise)} · ${payment.method.label}',
        ),
        if (payment.reference != null) Text('Reference: ${payment.reference}'),
        Text('Paid: ${payment.paidAt.toUtc().toIso8601String()} (UTC)'),
      ],
      if (result.subscription.cancellationReason != null)
        Text('Cancellation reason: ${result.subscription.cancellationReason}'),
    ],
  );
}
