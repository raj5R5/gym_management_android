import 'package:flutter/material.dart';
import '../../../shared/widgets/feedback_notice.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../members/data/member_failure.dart';
import '../../members/providers/member_providers.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/formatting/inr.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import 'payment_transaction_details.dart';
export '../../../shared/widgets/profile_section.dart';
export '../../../shared/widgets/page_controls.dart';

/// Refresh feedback accompanies a complete, same-scope verified snapshot.
class FinancialRefreshStatus extends StatelessWidget {
  const FinancialRefreshStatus({
    super.key,
    required this.loading,
    required this.error,
    required this.retry,
  });
  final bool loading;
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading) ...[
        const LinearProgressIndicator(),
        Semantics(
          liveRegion: true,
          child: const Text('Updating… Showing the last verified results.'),
        ),
      ],
      if (error != null && !loading) ...[
        Semantics(
          liveRegion: true,
          child: const Text(
            'Refresh failed. Showing the last verified results; amounts and member details may have changed.',
          ),
        ),
        BillingError(error: error, retry: retry),
      ],
    ],
  );
}

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
  Widget build(BuildContext context) => FeedbackNotice(
    message: error is BillingFailure
        ? (error as BillingFailure).message
        : error is MemberFailure
        ? (error as MemberFailure).message
        : 'Billing information could not be loaded. Please try again.',
    retry: retry,
  );
}

class BillingResultCard extends StatelessWidget {
  const BillingResultCard({super.key, required this.result, this.timezone});
  final BillingResult result;
  final String? timezone;
  @override
  Widget build(BuildContext context) => ProfileSection(
    title: 'Server confirmation',
    children: [
      Text(result.subscription.planName),
      Text('Status: ${result.subscription.status}'),
      Text(
        '${MaterialLocalizations.of(context).formatShortDate(result.subscription.startDate.value)} → ${MaterialLocalizations.of(context).formatShortDate(result.subscription.endDate.value)} (end exclusive, UTC)',
      ),
      Text(
        'Plan snapshot: ${formatInrPaise(result.subscription.pricePaise)} · ${result.subscription.durationDays} days',
      ),
      if (result.payment case final RecordedPayment payment) ...[
        PaymentTransactionDetails(payment: payment, timezone: timezone),
      ],
      if (result.subscription.cancellationReason != null)
        Text('Cancellation reason: ${result.subscription.cancellationReason}'),
    ],
  );
}
