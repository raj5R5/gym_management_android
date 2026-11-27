import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../memberships/data/billing_failure.dart';
import '../../memberships/data/outstanding_dues_repository.dart';
import '../../memberships/models/membership_eligibility.dart';
import '../../memberships/presentation/billing_components.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_details_cards.dart';
import 'member_list_widgets.dart';
import 'member_pay_now.dart';

class MemberCurrentMembershipCard extends ConsumerWidget {
  const MemberCurrentMembershipCard({
    super.key,
    required this.summary,
    required this.scope,
    required this.profileVerified,
  });
  final MemberSummary summary;
  final MemberScope scope;
  final bool profileVerified;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberMembershipsProvider(scope));
    final verified =
        !state.isLoading && !state.hasError && state.asData?.value != null;
    final blocker = verified ? blockingMembership(state.asData!.value!) : null;
    final membership = summary.currentSubscription ?? blocker;
    final previous = summary.history.firstOrNull;
    final currentMoney = currentMembershipBalance(summary) == null
        ? null
        : summary.currentPayments;
    final saved = membership?.payments;
    final savedVerified =
        membership != null &&
        saved != null &&
        saved.paidPaise + saved.balancePaise == membership.pricePaise;
    final paid = summary.currentSubscription != null
        ? currentMoney?.paidPaise
        : savedVerified
        ? saved.paidPaise
        : null;
    final due = summary.currentSubscription != null
        ? currentMoney?.balancePaise
        : savedVerified
        ? saved.balancePaise
        : null;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Current membership', style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (summary.currentSubscription == null) ...[
          Text('No current membership', style: theme.textTheme.titleLarge),
          if (membership != null) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'An upcoming membership is already saved. Purchase and renewal remain blocked until its end date.',
            ),
          ] else if (verified && previous?.status == 'expired') ...[
            const SizedBox(height: AppSpacing.sm),
            const StatusPill(
              label: 'Membership expired',
              tone: AppTone.neutral,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Renew to keep training. Any unpaid balance is shown below.',
            ),
          ] else if (verified && previous?.status == 'cancelled') ...[
            const SizedBox(height: AppSpacing.sm),
            const StatusPill(
              label: 'Previous membership cancelled',
              tone: AppTone.neutral,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('See membership history for the cancellation details.'),
          ] else if (verified && state.asData!.value!.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Choose a plan to start this member’s first membership.',
            ),
          ],
        ],
        if (membership != null) ...[
          if (summary.currentSubscription == null)
            const SizedBox(height: AppSpacing.md),
          MembershipAtAGlance(membership: membership),
          const SizedBox(height: AppSpacing.md),
          if (paid != null && due != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatInrPaise(paid)} paid of ${formatInrPaise(membership.pricePaise)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (due == 0)
                  const StatusPill(label: 'Fully Paid', tone: AppTone.positive),
              ],
            )
          else
            const Text(
              'Balance unavailable. Refresh to verify membership payments.',
            ),
        ] else if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('Checking membership eligibility…'),
          )
        else if (state.hasError)
          BillingError(
            error: state.error,
            retry: () => ref.invalidate(memberMembershipsProvider(scope)),
          ),
        if (summary.currentSubscription == null &&
            blocker == null &&
            verified &&
            profileVerified) ...[
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () =>
                context.push(membershipPath(scope, purchase: true)),
            icon: const Icon(Icons.add),
            label: const Text('Purchase membership'),
          ),
        ],
      ],
    );
  }
}

/// Plan, status, how much time is left and the dates, in that order.
class MembershipAtAGlance extends StatelessWidget {
  const MembershipAtAGlance({super.key, required this.membership, this.today});
  final Membership membership;

  /// For tests; defaults to the device's calendar day.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = today ?? DateTime.now();
    final day = DateTime.utc(now.year, now.month, now.day);
    final start = membership.startDate.value;
    final end = membership.endDate.value;
    DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final total = utc(end).difference(utc(start)).inDays;
    final left = utc(end).difference(day).inDays;
    final upcoming = utc(start).isAfter(day);
    final running = membership.currentlyActive && !upcoming && left > 0;
    final headline = upcoming
        ? 'Starts in ${utc(start).difference(day).inDays} days'
        : running
        ? '$left ${left == 1 ? 'day' : 'days'} left'
        : null;
    final notes = [
      if (membership.frozenDays > 0)
        'includes ${membership.frozenDays} frozen ${membership.frozenDays == 1 ? 'day' : 'days'}',
      if (membership.discountPaise > 0)
        '${formatCompactInrPaise(membership.discountPaise)} discount given',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                membership.planName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              label: 'Membership status',
              child: MembershipStatusPill(membership: membership),
            ),
          ],
        ),
        if (headline != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            headline,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (running && total > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: ((total - left) / total).clamp(0.0, 1.0),
              semanticsLabel: 'Membership time used',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        MembershipDateRange(start: start, end: end),
        if (notes.isNotEmpty)
          Text(notes.join(' · '), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Show the existing verified dues calculation alongside the server's lifetime
/// successful-payment total. Their scopes are labeled rather than treated as a
/// single invoice. Same-scope content survives refresh, but Pay Now still uses
/// the existing live-state gate and durable payment controller.
class MemberPaymentSummaryCard extends ConsumerStatefulWidget {
  const MemberPaymentSummaryCard({
    super.key,
    required this.scope,
    required this.summary,
    this.profileVerified = true,
    this.timezone,
  });
  final MemberScope scope;
  final MemberSummary summary;
  final bool profileVerified;
  final String? timezone;
  @override
  ConsumerState<MemberPaymentSummaryCard> createState() =>
      _MemberPaymentSummaryCardState();
}

class _MemberPaymentSummaryCardState
    extends ConsumerState<MemberPaymentSummaryCard> {
  int? _verifiedDues;
  MemberScope? _scope;
  Object? _repository;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(memberRepositoryProvider);
    if (_scope != widget.scope || !identical(_repository, repository)) {
      _scope = widget.scope;
      _repository = repository;
      _verifiedDues = null;
    }
    final state = ref.watch(memberMembershipsProvider(widget.scope));
    final records = state.asData?.value;
    BillingFailure? invalid;
    final verified = !state.isLoading && !state.hasError && records != null;
    if (verified) {
      try {
        final unpaid = verifiedUnpaidMemberships(records);
        _verifiedDues = OutstandingDues([
          OutstandingMember(widget.summary.member, unpaid),
        ]).totalPaise;
      } on BillingFailure catch (error) {
        invalid = error;
      } on FormatException {
        invalid = const BillingFailure(
          'Membership balances could not be verified. Refresh history.',
        );
      }
    }
    final fresh = verified && invalid == null;
    final theme = Theme.of(context);
    final dues = _verifiedDues;
    final owes = dues != null && dues > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fresh
                        ? 'Current outstanding'
                        : dues == null
                        ? 'Outstanding balance'
                        : 'Last verified dues',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    dues == null ? 'Unavailable' : formatInrPaise(dues),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: owes
                          ? PendingColors.accentFor(theme.brightness)
                          : theme.colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (owes)
          Text(
            'All unpaid memberships, including expired plans.',
            style: theme.textTheme.bodySmall,
          )
        else if (fresh && dues == 0)
          Text('No outstanding dues.', style: theme.textTheme.bodySmall),
        if (!fresh && dues != null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Refresh in progress or unavailable. The displayed dues are the last verified amount.',
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        MemberPayNow(
          key: ValueKey(widget.scope),
          scope: widget.scope,
          member: widget.summary.member,
          profileVerified: widget.profileVerified,
        ),
        // Recovery stays beside the balance and canonical collection control.
        MemberPaymentRecovery(
          scope: widget.scope,
          member: widget.summary.member,
        ),
        if (invalid != null) ...[
          // MemberPaymentRecovery renders the balance failure and retry action.
          const Text(
            'No payment can be collected until the balance is verified.',
          ),
        ],
      ],
    );
  }
}

/// Money already received: the total, the latest payment and the way to
/// the full history.
class MemberPaymentsSection extends StatelessWidget {
  const MemberPaymentsSection({
    super.key,
    required this.scope,
    required this.summary,
    this.timezone,
  });
  final MemberScope scope;
  final MemberSummary summary;
  final String? timezone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payments = summary.payments;
    return ProfileSection(
      title: 'Payments',
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Total paid'),
            Text(
              formatInrPaise(payments.totalPaise),
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '· ${payments.count} ${payments.count == 1 ? 'payment' : 'payments'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        MemberLatestPayment(payments: payments, timezone: timezone),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.push(membershipPath(scope)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Membership & payments'),
          ),
        ),
      ],
    );
  }
}
