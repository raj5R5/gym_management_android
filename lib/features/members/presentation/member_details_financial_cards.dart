import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
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
    return ProfileSection(
      title: 'Current membership',
      compactHeader: true,
      icon: Icons.card_membership_outlined,
      tone: AppTone.neutral,
      children: [
        if (summary.currentSubscription == null) ...[
          const Text('No current membership.'),
          if (membership != null) ...[
            const SizedBox(height: AppSpacing.sm),
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
              'Review membership history for renewal. Any unpaid balance is still shown below.',
            ),
          ] else if (verified && previous?.status == 'cancelled') ...[
            const SizedBox(height: AppSpacing.sm),
            const StatusPill(
              label: 'Previous membership cancelled',
              tone: AppTone.neutral,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Open membership history to review the cancellation details.',
            ),
          ] else if (verified && state.asData!.value!.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Choose a plan to start this member’s first membership.',
            ),
          ],
        ],
        if (membership != null) ...[
          const SizedBox(height: AppSpacing.md),
          SavedMembershipSummary(
            membership: membership,
            compact: true,
            emphasizeDuration: true,
          ),
          const Divider(height: AppSpacing.xl),
          MemberAmounts(
            paidPaise: paid,
            balancePaise: due,
            compact: true,
            paidLabel: 'Paid for this plan',
            dueLabel: 'Due for this plan',
          ),
          if (due == null)
            const Text(
              'Balance unavailable. Refresh to verify membership payments.',
            ),
          if (due == 0)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: StatusPill(label: 'Fully Paid', tone: AppTone.positive),
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
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => context.push(membershipPath(scope)),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Membership & payments'),
        ),
        if (summary.currentSubscription == null &&
            blocker == null &&
            verified &&
            profileVerified)
          OutlinedButton.icon(
            onPressed: () =>
                context.push(membershipPath(scope, purchase: true)),
            icon: const Icon(Icons.add),
            label: const Text('Purchase membership'),
          ),
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
    return ProfileSection(
      title: 'Payment summary',
      compactHeader: true,
      icon: Icons.account_balance_wallet_outlined,
      tone: AppTone.neutral,
      // The balance is the main block of this screen.
      card: true,
      children: [
        Text(
          fresh
              ? 'Current outstanding'
              : _verifiedDues == null
              ? 'Outstanding balance'
              : 'Last verified dues',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _verifiedDues == null
              ? 'Unavailable'
              : formatInrPaise(_verifiedDues!),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontFamily: 'Inter',
            color: _verifiedDues != null && _verifiedDues! > 0
                ? PendingColors.accentFor(Theme.of(context).brightness)
                : Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          fresh && _verifiedDues == 0
              ? 'No outstanding dues across non-cancelled memberships.'
              : 'Across all unpaid, non-cancelled memberships — including expired plans.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!fresh && _verifiedDues != null)
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
        const Divider(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Total paid', style: Theme.of(context).textTheme.bodyMedium),
            Text(
              formatInrPaise(widget.summary.payments.totalPaise),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        Text(
          'Successful payments: ${widget.summary.payments.count}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        MemberLatestPayment(
          payments: widget.summary.payments,
          timezone: widget.timezone,
        ),
        TextButton.icon(
          onPressed: () => context.push(membershipPath(widget.scope)),
          icon: const Icon(Icons.history),
          label: const Text('View payment history'),
        ),
      ],
    );
  }
}
