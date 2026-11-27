import '../../receipts/receipt.dart';
import '../../members/presentation/member_list_widgets.dart';
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
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/page_section.dart';
import '../../members/presentation/member_details_financial_cards.dart';

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
            Text(
              '${data.member.name} · ${data.member.memberCode}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '${formatInrPaise(data.payments.totalPaise)} paid in ${data.payments.count} ${data.payments.count == 1 ? 'payment' : 'payments'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (summary.hasError)
            BillingError(
              error: summary.error,
              retry: () => ref.invalidate(memberSummaryProvider(scope)),
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
          const SizedBox(height: AppSpacing.lg),
          // The plan now, read like a bill.
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Current membership',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (history.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (history.hasError)
                  BillingError(
                    error: history.error,
                    retry: () =>
                        ref.invalidate(memberHistoryProvider(historyRequest)),
                  )
                else if (history.asData?.value
                    case final MembershipHistory data)
                  if (data.current == null)
                    const Text('No current membership.')
                  else ...[
                    MembershipAtAGlance(membership: data.current!),
                    const SizedBox(height: AppSpacing.md),
                    if (data.current!.payments
                        case final MembershipPayments amounts) ...[
                      BillRow(
                        label: 'Plan price',
                        amountPaise: data.current!.pricePaise,
                      ),
                      BillRow(label: 'Paid', amountPaise: amounts.paidPaise),
                      const Divider(height: AppSpacing.lg),
                      BillRow(
                        label: 'Balance',
                        amountPaise: amounts.balancePaise,
                        total: true,
                        color: amounts.balancePaise > 0
                            ? AppPalette.accentLight
                            : null,
                      ),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => context.push(
                          membershipPath(
                            scope,
                            subscriptionId: data.current!.id,
                          ),
                        ),
                        child: const Text('View membership'),
                      ),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: mutation.isLoading
                ? null
                : () => context.push(membershipPath(scope, purchase: true)),
            icon: const Icon(Icons.add),
            label: const Text('Purchase membership'),
          ),
          ProfileSection(
            title: 'Membership history',
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
                SeparatedRows(
                  children: [
                    for (final subscription in data.subscriptions)
                      Builder(
                        builder: (tileContext) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(subscription.planName),
                          subtitle: Text(
                            '${membershipStatusLabel(subscription)} · '
                            '${formatCompactInrPaise(subscription.pricePaise)} · '
                            '${MaterialLocalizations.of(context).formatShortMonthDay(subscription.startDate.value)} – '
                            '${MaterialLocalizations.of(context).formatShortDate(subscription.endDate.value)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => pushFromCard(
                            tileContext,
                            membershipPath(
                              scope,
                              subscriptionId: subscription.id,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                SeparatedRows(
                  indent: 40,
                  children: [
                    for (final payment in data.items)
                      PaymentRow(
                        payment: payment,
                        timezone: timezone,
                        onTap: () => context.push(
                          membershipPath(
                            scope,
                            subscriptionId: payment.subscriptionId,
                          ),
                        ),
                        onReceipt: () => shareReceipt(context, ref, payment.id),
                      ),
                  ],
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
