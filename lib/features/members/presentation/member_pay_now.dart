import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../memberships/data/billing_failure.dart';
import '../../memberships/models/membership_eligibility.dart';
import '../../memberships/presentation/billing_components.dart';
import '../../memberships/presentation/record_payment_sheet.dart';
import '../../memberships/providers/payment_providers.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';

class MemberPayNow extends ConsumerStatefulWidget {
  const MemberPayNow({
    super.key,
    required this.scope,
    required this.member,
    this.profileVerified = true,
  });
  final MemberScope scope;
  final MemberProfile member;
  final bool profileVerified;
  @override
  ConsumerState<MemberPayNow> createState() => _MemberPayNowState();
}

class _MemberPayNowState extends ConsumerState<MemberPayNow> {
  bool _opening = false;
  bool get _current =>
      mounted && matchesScope(ref.read(adminGymProvider), widget.scope);
  Future<void> _open(List<Membership> due) async {
    if (_opening || !_current) return;
    setState(() => _opening = true);
    try {
      final id = due.length == 1
          ? due.single.id
          : await showModalBottomSheet<String>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (_) => _ChooseUnpaidMembership(scope: widget.scope),
            );
      if (!mounted || !_current || id == null) return;
      final state = ref.read(memberMembershipsProvider(widget.scope));
      if (state.isLoading || state.hasError || state.asData?.value == null) {
        return;
      }
      final selected = verifiedUnpaidMemberships(
        state.asData!.value!,
      ).where((membership) => membership.id == id).firstOrNull;
      if (selected == null) return;
      await showRecordPayment(
        context,
        (member: widget.scope, subscriptionId: selected.id),
        widget.member.name,
        memberCode: widget.member.memberCode,
      );
    } on BillingFailure catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!matchesScope(ref.watch(adminGymProvider), widget.scope)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(memberMembershipsProvider(widget.scope));
    if (!widget.profileVerified || state.isLoading || state.hasError) {
      return const SizedBox.shrink();
    }
    final records = state.asData?.value;
    if (records == null) return const SizedBox.shrink();
    final List<Membership> due;
    try {
      due = verifiedUnpaidMemberships(records);
    } on BillingFailure {
      return const SizedBox.shrink();
    }
    if (due.isEmpty) return const SizedBox.shrink();
    // A new collection is offered only after the canonical controller has read
    // durable operation state. Unresolved/confirmed operations use recovery below.
    final collectible = <Membership>[];
    for (final membership in due) {
      final paymentScope = (
        member: widget.scope,
        subscriptionId: membership.id,
      );
      final operation = ref.watch(paymentCollectionProvider(paymentScope));
      final controller = ref.read(
        paymentCollectionProvider(paymentScope).notifier,
      );
      if (!operation.isLoading &&
          !operation.hasError &&
          !controller.busy &&
          !controller.blocked &&
          !controller.hasSavedOperation &&
          controller.confirmed == null) {
        collectible.add(membership);
      }
    }
    if (collectible.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Align(
          alignment: Alignment.centerRight,
          heightFactor: 1,
          child: FloatingActionButton.extended(
            heroTag: 'member-pay-now',
            onPressed: _opening ? null : () => _open(collectible),
            backgroundColor: _opening
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : null,
            foregroundColor: _opening
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : null,
            icon: Icon(
              _opening ? Icons.hourglass_top_outlined : Icons.add_card_outlined,
            ),
            label: Text(_opening ? 'Opening payment…' : 'Pay Now'),
          ),
        ),
      ),
    );
  }
}

/// Secondary recovery entry points preserve exact retries and acknowledgement;
/// they never offer a second primary collection action beside the floating CTA.
class MemberPaymentRecovery extends ConsumerWidget {
  const MemberPaymentRecovery({
    super.key,
    required this.scope,
    required this.member,
  });
  final MemberScope scope;
  final MemberProfile member;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!matchesScope(ref.watch(adminGymProvider), scope)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(memberMembershipsProvider(scope));
    if (state.isLoading) return const Text('Checking unpaid memberships…');
    if (state.hasError) {
      return BillingError(
        error: state.error,
        retry: () => ref.invalidate(memberMembershipsProvider(scope)),
      );
    }
    final records = state.asData?.value;
    if (records == null) return const SizedBox.shrink();
    try {
      verifiedUnpaidMemberships(records);
    } on BillingFailure catch (failure) {
      return BillingError(
        error: failure,
        retry: () => ref.invalidate(memberMembershipsProvider(scope)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cancellation can arrive from another session while an operation is
        // unresolved. Recovery remains reachable even when collection is barred.
        for (final membership in records)
          _SavedMemberPayment(
            scope: (member: scope, subscriptionId: membership.id),
            member: member,
            plan: membership.planName,
          ),
      ],
    );
  }
}

class _SavedMemberPayment extends ConsumerWidget {
  const _SavedMemberPayment({
    required this.scope,
    required this.member,
    required this.plan,
  });
  final PaymentScope scope;
  final MemberProfile member;
  final String plan;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(paymentCollectionProvider(scope));
    final controller = ref.read(paymentCollectionProvider(scope).notifier);
    if (operation.isLoading) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Checking saved payment',
      );
    }
    if (operation.hasError ||
        controller.blocked ||
        controller.hasSavedOperation ||
        controller.confirmed != null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text('Review saved payment · $plan'),
        onPressed: controller.busy
            ? null
            : () => showRecordPayment(
                context,
                scope,
                member.name,
                memberCode: member.memberCode,
              ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ChooseUnpaidMembership extends ConsumerWidget {
  const _ChooseUnpaidMembership({required this.scope});
  final MemberScope scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberMembershipsProvider(scope));
    final List<Membership> due;
    if (!matchesScope(ref.watch(adminGymProvider), scope) ||
        state.isLoading ||
        state.hasError ||
        state.asData?.value == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Membership balances are unavailable. Close this sheet and refresh the member.',
        ),
      );
    }
    try {
      due = verifiedUnpaidMemberships(state.asData!.value!);
    } on BillingFailure {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Membership balances could not be verified. Close this sheet and refresh the member.',
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose membership to pay',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close membership selection',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text('Payments apply only to the membership you select.'),
          for (final membership in due)
            Card(
              child: ListTile(
                key: ValueKey('pay-membership-${membership.id}'),
                onTap: () => Navigator.pop(context, membership.id),
                title: Text(membership.planName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MembershipDateRange(
                      start: membership.startDate.value,
                      end: membership.endDate.value,
                    ),
                    Text(
                      '${membership.status == 'expired' ? 'Expired · ' : ''}${formatInrPaise(membership.payments!.balancePaise)} remaining',
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ),
    );
  }
}
