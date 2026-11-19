import '../../../shared/widgets/membership_date_range.dart';
import '../../receipts/receipt.dart';
import '../../members/presentation/member_list_widgets.dart';
import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../../shared/formatting/inr.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import 'payment_transaction_details.dart';
import '../../../shared/widgets/card_reveal.dart';

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({
    super.key,
    required this.memberId,
    required this.gymId,
  });
  final String memberId;
  final String? gymId;
  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  int _historyPage = 1, _paymentPage = 1;
  @override
  void didUpdateWidget(MembershipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberId != widget.memberId ||
        oldWidget.gymId != widget.gymId) {
      _historyPage = _paymentPage = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final timezone = ref.watch(paymentTimezoneProvider(gym)).asData?.value;
    final scope = scopeFor(gym, widget.memberId);
    final historyRequest = (scope: scope, page: _historyPage);
    final paymentRequest = (scope: scope, page: _paymentPage);
    final history = ref.watch(memberHistoryProvider(historyRequest));
    final payments = ref.watch(paymentHistoryProvider(paymentRequest));
    final summary = ref.watch(memberSummaryProvider(scope));
    final mutation = ref.watch(billingMutationProvider(scope));
    Future<void> refresh() async {
      ref.invalidate(memberHistoryProvider(historyRequest));
      ref.invalidate(paymentHistoryProvider(paymentRequest));
      ref.invalidate(memberSummaryProvider(scope));
      await Future.wait([
        ref
            .read(memberHistoryProvider(historyRequest).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(paymentHistoryProvider(paymentRequest).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(memberSummaryProvider(scope).future)
            .then<void>((_) {}, onError: (Object _) {}),
      ]);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to member',
                onPressed: () => context.go(memberPath(scope)),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Membership & payments',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh billing',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (summary.asData?.value case final MemberSummary data) ...[
            Text('${data.member.name} · ${data.member.memberCode}'),
            Text(
              'Successful payments: ${data.payments.count} · ${formatInrPaise(data.payments.totalPaise)}',
            ),
          ] else if (summary.hasError)
            BillingError(
              error: summary.error,
              retry: () => ref.invalidate(memberSummaryProvider(scope)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: mutation.isLoading
                ? null
                : () => context.push(membershipPath(scope, purchase: true)),
            icon: const Icon(Icons.add),
            label: const Text('Purchase membership'),
          ),
          if (mutation.hasError) ...[
            BillingError(error: mutation.error),
            OutlinedButton(
              onPressed: mutation.isLoading
                  ? null
                  : () async {
                      final checked = await ref
                          .read(billingMutationProvider(scope).notifier)
                          .recheck();
                      if (checked && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'History refreshed. Review memberships and payments before another attempt.',
                            ),
                          ),
                        );
                      }
                    },
              child: const Text('Recheck membership and payments'),
            ),
          ],
          ProfileSection(
            title: 'Current membership',
            icon: Icons.card_membership_outlined,
            children: [
              if (history.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (history.hasError)
                BillingError(
                  error: history.error,
                  retry: () =>
                      ref.invalidate(memberHistoryProvider(historyRequest)),
                )
              else if (history.asData?.value case final MembershipHistory data)
                if (data.current == null)
                  const Text('No current membership.')
                else ...[
                  membershipText(data.current!),
                  if (data.current!.payments
                      case final MembershipPayments amounts) ...[
                    IconLabel(
                      'Successful paid: ${formatInrPaise(amounts.paidPaise)}',
                      icon: Icons.payments_outlined,
                    ),
                    IconLabel(
                      'Balance: ${formatInrPaise(amounts.balancePaise)}',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                  TextButton(
                    onPressed: () => context.push(
                      membershipPath(scope, subscriptionId: data.current!.id),
                    ),
                    child: const Text('View membership'),
                  ),
                ],
            ],
          ),
          ProfileSection(
            title: 'Membership history',
            icon: Icons.history,
            children: [
              if (history.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (history.hasError)
                BillingError(
                  error: history.error,
                  retry: () =>
                      ref.invalidate(memberHistoryProvider(historyRequest)),
                )
              else if (history.asData?.value
                  case final MembershipHistory data) ...[
                if (data.subscriptions.isEmpty)
                  const Text('No membership history.'),
                ...data.subscriptions.map(
                  (subscription) => Builder(
                    builder: (tileContext) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(subscription.planName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MembershipStatusPill(membership: subscription),
                          const SizedBox(height: 8),
                          MembershipDateRange(
                            start: subscription.startDate.value,
                            end: subscription.endDate.value,
                          ),
                          Text(
                            '${formatInrPaise(subscription.pricePaise)} · End exclusive, gym timezone',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => pushFromCard(
                        tileContext,
                        membershipPath(scope, subscriptionId: subscription.id),
                      ),
                    ),
                  ),
                ),
                PageControls(
                  page: data.pagination.page,
                  total: data.pagination.total,
                  previous: data.pagination.hasPrevious
                      ? () => setState(() => _historyPage--)
                      : null,
                  next: data.pagination.hasNext
                      ? () => setState(() => _historyPage++)
                      : null,
                ),
              ],
            ],
          ),
          ProfileSection(
            title: 'Successful payment history',
            icon: Icons.receipt_long_outlined,
            children: [
              if (payments.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (payments.hasError)
                BillingError(
                  error: payments.error,
                  retry: () =>
                      ref.invalidate(paymentHistoryProvider(paymentRequest)),
                )
              else if (payments.asData?.value
                  case final BillingPage<RecordedPayment> data) ...[
                if (data.items.isEmpty) const Text('No successful payments.'),
                ...data.items.map(
                  (payment) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PaymentTransactionDetails(
                          payment: payment,
                          timezone: timezone,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => context.push(
                                membershipPath(
                                  scope,
                                  subscriptionId: payment.subscriptionId,
                                ),
                              ),
                              child: const Text('View associated membership'),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  shareReceipt(context, ref, payment.id),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Share receipt'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                PageControls(
                  page: data.pagination.page,
                  total: data.pagination.total,
                  previous: data.pagination.hasPrevious
                      ? () => setState(() => _paymentPage--)
                      : null,
                  next: data.pagination.hasNext
                      ? () => setState(() => _paymentPage++)
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
