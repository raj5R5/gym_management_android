import '../../../shared/widgets/icon_label.dart';
import '../../receipts/receipt.dart';
import '../../adjustments/adjustment_widgets.dart';
import '../../receipts/upi_collect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/formatting/payment_date.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import 'record_payment_sheet.dart';
import 'renewal_confirmation_sheet.dart';
import 'cancellation_confirmation_sheet.dart';
import '../providers/renewal_providers.dart';

class MembershipDetailPage extends ConsumerStatefulWidget {
  const MembershipDetailPage({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.subscriptionId,
  });
  final String memberId, subscriptionId;
  final String? gymId;
  @override
  ConsumerState<MembershipDetailPage> createState() =>
      _MembershipDetailPageState();
}

class _MembershipDetailPageState extends ConsumerState<MembershipDetailPage> {
  BillingResult? _result;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MembershipDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberId != widget.memberId ||
        oldWidget.gymId != widget.gymId ||
        oldWidget.subscriptionId != widget.subscriptionId) {
      _result = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final timezone = ref.watch(paymentTimezoneProvider(gym)).asData?.value;
    final scope = scopeFor(gym, widget.memberId);
    final request = (scope: scope, subscriptionId: widget.subscriptionId);
    final detail = ref.watch(membershipDetailProvider(request));
    final member = ref.watch(memberProfileProvider(scope));
    final collectionScope = (
      member: scope,
      subscriptionId: widget.subscriptionId,
    );
    final collection = ref.watch(paymentCollectionProvider(collectionScope));
    final collector = ref.read(
      paymentCollectionProvider(collectionScope).notifier,
    );
    final savedPayment =
        collector.hasSavedOperation ||
        (collection.error is BillingFailure &&
            (collection.error! as BillingFailure).uncertain);
    final mutation = ref.watch(billingMutationProvider(scope));
    final busy = mutation.isLoading;
    final blocked =
        mutation.error is BillingFailure &&
        (mutation.error as BillingFailure).uncertain;
    return PopScope(
      canPop: !busy,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to membership',
                onPressed: busy
                    ? null
                    : () => context.go(membershipPath(scope)),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Membership details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh membership',
                onPressed: busy
                    ? null
                    : () => ref.invalidate(membershipDetailProvider(request)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_result case final BillingResult result) ...[
            if (result.subscription.status == 'cancelled')
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Membership cancelled. History has been kept. No refund was made.',
                ),
              ),
            BillingResultCard(result: result, timezone: timezone),
          ],
          if (detail.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (detail.hasError)
            BillingError(
              error: detail.error,
              retry: () => ref.invalidate(membershipDetailProvider(request)),
            )
          else if (detail.asData?.value case final MembershipDetail data) ...[
            ProfileSection(
              title: 'Plan & balance',
              icon: Icons.card_membership_outlined,
              children: [
                membershipText(data.subscription),
                IconLabel(
                  'Successful paid: ${formatInrPaise(data.payments.paidPaise)}',
                  icon: Icons.payments_outlined,
                ),
                IconLabel(
                  'Balance: ${formatInrPaise(data.payments.balancePaise)}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                if (data.subscription.cancelledAt != null)
                  IconLabel(
                    'Cancelled: ${formatPaymentDateTime(MaterialLocalizations.of(context), data.subscription.cancelledAt!, timezone: timezone)}',
                    icon: Icons.event_busy_outlined,
                  ),
                if (data.subscription.cancellationReason != null)
                  IconLabel(
                    'Reason: ${data.subscription.cancellationReason}',
                    icon: Icons.notes_outlined,
                  ),
                if (data.subscription.previousId != null)
                  const Text('Renewal of a previous membership.'),
              ],
            ),
            if (mutation.hasError) BillingError(error: mutation.error),
            if (blocked)
              OutlinedButton(
                onPressed: () => context.go(membershipPath(scope)),
                child: const Text('Check membership and payment history'),
              ),
            if (savedPayment)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => showRecordPayment(
                        context,
                        collectionScope,
                        member.asData?.value?.name,
                        memberCode: member.asData?.value?.memberCode,
                      ),
                icon: const Icon(Icons.restore),
                label: const Text('Review saved payment'),
              ),
            if (data.subscription.status != 'cancelled') ...[
              if (data.payments.balancePaise > 0 && !savedPayment)
                FilledButton.icon(
                  onPressed: busy || blocked
                      ? null
                      : () async {
                          final payment = await showRecordPayment(
                            context,
                            (
                              member: scope,
                              subscriptionId: widget.subscriptionId,
                            ),
                            member.asData?.value?.name,
                            memberCode: member.asData?.value?.memberCode,
                          );
                          if (context.mounted) {
                            offerReceipt(context, ref, payment);
                          }
                        },
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Record Payment'),
                ),
              if (data.payments.balancePaise > 0 && !savedPayment)
                OutlinedButton.icon(
                  onPressed: busy || blocked
                      ? null
                      : () async {
                          final record = await showUpiCollect(
                            context,
                            amountPaise: data.payments.balancePaise,
                            memberName: member.asData?.value?.name ?? 'Member',
                            memberCode: member.asData?.value?.memberCode ?? '',
                            planName: data.subscription.planName,
                          );
                          if (!record || !context.mounted) return;
                          final payment = await showRecordPayment(
                            context,
                            (
                              member: scope,
                              subscriptionId: widget.subscriptionId,
                            ),
                            member.asData?.value?.name,
                            memberCode: member.asData?.value?.memberCode,
                          );
                          if (context.mounted) {
                            offerReceipt(context, ref, payment);
                          }
                        },
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Collect by UPI'),
                ),
              OutlinedButton(
                onPressed: busy || blocked
                    ? null
                    : () async {
                        ref.invalidate(memberProfileProvider(scope));
                        ref.invalidate(membershipDetailProvider(request));
                        final result = await showCancellationConfirmation(
                          context,
                          request,
                        );
                        if (!mounted ||
                            !matchesScope(ref.read(adminGymProvider), scope) ||
                            result == null) {
                          return;
                        }
                        setState(() => _result = result);
                        if (_scroll.hasClients) {
                          _scroll.jumpTo(0);
                        }
                      },
                child: const Text('Cancel membership'),
              ),
              FilledButton(
                onPressed: busy || blocked
                    ? null
                    : () async {
                        ref.invalidate(membershipDetailProvider(request));
                        ref.invalidate(renewalPreviousPlanProvider(request));
                        ref.invalidate(
                          activePlansProvider((scope: scope, page: 1)),
                        );
                        final result = await showRenewalConfirmation(
                          context,
                          scope,
                          widget.subscriptionId,
                        );
                        if (!mounted ||
                            !matchesScope(ref.read(adminGymProvider), scope)) {
                          return;
                        }
                        setState(() => _result = result);
                        if (result != null && _scroll.hasClients) {
                          _scroll.jumpTo(0);
                        }
                      },
                child: const Text('Review renewal'),
              ),
            ],
            // Less frequent adjustments sit below the main payment actions.
            if (data.subscription.status != 'cancelled')
              MembershipAdjustmentsCard(
                scope: scope,
                subscriptionId: widget.subscriptionId,
              ),
          ],
        ],
      ),
    );
  }
}
