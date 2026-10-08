import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../../shared/formatting/inr.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import 'billing_components.dart';

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
  final _reason = TextEditingController();
  String? _action;
  BillingResult? _result;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MembershipDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberId != widget.memberId ||
        oldWidget.gymId != widget.gymId ||
        oldWidget.subscriptionId != widget.subscriptionId) {
      _action = null;
      _result = null;
      _reason.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final scope = scopeFor(gym, widget.memberId);
    final request = (scope: scope, subscriptionId: widget.subscriptionId);
    final detail = ref.watch(membershipDetailProvider(request));
    final mutation = ref.watch(billingMutationProvider(scope));
    final busy = mutation.isLoading;
    final blocked =
        mutation.error is BillingFailure &&
        (mutation.error as BillingFailure).uncertain;
    return PopScope(
      canPop: !busy,
      child: ListView(
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
          if (_result case final BillingResult result)
            BillingResultCard(result: result),
          if (detail.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (detail.hasError)
            BillingError(
              error: detail.error,
              retry: () => ref.invalidate(membershipDetailProvider(request)),
            )
          else if (detail.asData?.value case final MembershipDetail data) ...[
            ProfileSection(
              title: data.subscription.planName,
              children: [
                membershipText(data.subscription),
                Text(
                  'Successful paid: ${formatInrPaise(data.payments.paidPaise)}',
                ),
                Text('Balance: ${formatInrPaise(data.payments.balancePaise)}'),
                if (data.subscription.cancelledAt != null)
                  Text(
                    'Cancelled: ${data.subscription.cancelledAt!.toUtc().toIso8601String()} (UTC)',
                  ),
                if (data.subscription.cancellationReason != null)
                  Text('Reason: ${data.subscription.cancellationReason}'),
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
            if (_action == null && data.subscription.status != 'cancelled') ...[
              OutlinedButton(
                onPressed: busy || blocked
                    ? null
                    : () => setState(() => _action = 'cancel'),
                child: const Text('Cancel membership'),
              ),
              FilledButton(
                onPressed: busy || blocked
                    ? null
                    : () => setState(() => _action = 'renew'),
                child: const Text('Review renewal'),
              ),
            ],
            if (_action != null)
              ProfileSection(
                title: _action == 'cancel'
                    ? 'Confirm cancellation'
                    : 'Confirm renewal',
                children: [
                  if (_action == 'cancel') ...[
                    const Text(
                      'Cancel this membership? Membership and payment history will be preserved. No refund is created.',
                    ),
                    TextField(
                      key: const ValueKey('cancellationReason'),
                      controller: _reason,
                      enabled: !busy,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional)',
                      ),
                    ),
                  ] else
                    const Text(
                      'Renew this membership using the current plan terms? The server determines dates, price snapshot and eligibility. No payment is recorded by renewal.',
                    ),
                  if (busy) const Center(child: CircularProgressIndicator()),
                  FilledButton(
                    onPressed: busy || blocked
                        ? null
                        : () async {
                            final controller = ref.read(
                              billingMutationProvider(scope).notifier,
                            );
                            final result = _action == 'cancel'
                                ? await controller.cancel(
                                    widget.subscriptionId,
                                    _reason.text,
                                  )
                                : await controller.renew(widget.subscriptionId);
                            if (!mounted ||
                                !matchesScope(
                                  ref.read(adminGymProvider),
                                  scope,
                                )) {
                              return;
                            }
                            setState(() {
                              _result = result;
                              _action = null;
                            });
                          },
                    child: Text(
                      _action == 'cancel'
                          ? 'Confirm cancellation'
                          : 'Confirm renewal',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _action = null),
                    child: const Text('Keep unchanged'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
