import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
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
      icon: Icons.card_membership_outlined,
      subtitle: 'Saved plan, dates and membership balance',
      tone: AppTone.neutral,
      children: [
        if (summary.currentSubscription == null) ...[
          const Text('No current membership.'),
          if (membership != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'An unexpired or upcoming membership is already saved. Purchase and renewal are blocked until its end date.',
            ),
          ],
        ],
        if (membership != null) ...[
          const SizedBox(height: AppSpacing.md),
          SavedMembershipSummary(membership: membership),
          const SizedBox(height: AppSpacing.md),
          MemberAmounts(paidPaise: paid, balancePaise: due),
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
          FilledButton.icon(
            style: AppButtonStyles.primary(context),
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
  });
  final MemberScope scope;
  final MemberSummary summary;
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
      icon: Icons.account_balance_wallet_outlined,
      subtitle: 'Successful payments and current unpaid balances',
      tone: AppTone.neutral,
      children: [
        MemberAmounts(
          paidLabel: 'Total paid',
          paidPaise: widget.summary.payments.totalPaise,
          dueLabel: fresh
              ? 'Current outstanding'
              : _verifiedDues == null
              ? 'Outstanding balance'
              : 'Last verified dues',
          balancePaise: _verifiedDues,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Paid includes successful payment history. Dues include all non-cancelled unpaid memberships.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Successful payments: ${widget.summary.payments.count}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (!fresh && _verifiedDues != null)
          const Text(
            'Refresh in progress or unavailable. The displayed dues are the last verified amount.',
          ),
        // Secondary recovery entries share the canonical collection controller
        // with the floating action and the existing receipt sheet.
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
        MemberLatestPayment(payments: widget.summary.payments),
        TextButton.icon(
          onPressed: () => context.push(membershipPath(widget.scope)),
          icon: const Icon(Icons.history),
          label: const Text('View payment history'),
        ),
      ],
    );
  }
}
