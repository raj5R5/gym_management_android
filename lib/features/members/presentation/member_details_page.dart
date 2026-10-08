import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/formatting/inr.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import '../../memberships/presentation/billing_components.dart'
    show membershipPath;

class MemberDetailsPage extends ConsumerStatefulWidget {
  const MemberDetailsPage({
    super.key,
    required this.memberId,
    required this.gymId,
  });
  final String memberId;
  final String? gymId;
  @override
  ConsumerState<MemberDetailsPage> createState() => _MemberDetailsPageState();
}

class _MemberDetailsPageState extends ConsumerState<MemberDetailsPage> {
  int _historyPage = 1;
  @override
  void didUpdateWidget(MemberDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gymId != widget.gymId ||
        oldWidget.memberId != widget.memberId) {
      _historyPage = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final scope = scopeFor(gym, widget.memberId);
    final summary = ref.watch(memberSummaryProvider(scope));
    final request = (scope: scope, page: _historyPage);
    Future<void> refresh() async {
      ref.invalidate(memberSummaryProvider(scope));
      ref.invalidate(memberHistoryProvider(request));
      // AsyncValue owns safe failures; completing the gesture doesn't expose them.
      await Future.wait([
        ref
            .read(memberSummaryProvider(scope).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(memberHistoryProvider(request).future)
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
                tooltip: 'Back to Members',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.members);
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Member details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (summary.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (summary.hasError)
            MemberError(
              error: summary.error,
              retry: () => ref.invalidate(memberSummaryProvider(scope)),
            )
          else if (summary.asData?.value case final MemberSummary data) ...[
            MemberSection(
              title: data.member.name,
              children: [
                Text('Member code: ${data.member.memberCode}'),
                Text('Phone: ${data.member.phone}'),
                Text('Status: ${data.member.status.name}'),
                Text(
                  data.branch == null
                      ? 'No current branch available'
                      : 'Branch: ${data.branch!.name} (${data.branch!.status})',
                ),
                if (data.member.dateOfBirth != null)
                  Text('Date of birth: ${data.member.dateOfBirth}'),
                if (data.member.gender != null)
                  Text('Gender: ${data.member.gender}'),
                if (data.member.address != null)
                  Text('Address: ${data.member.address!.display}'),
                if (data.member.emergencyContact
                    case final EmergencyContact contact)
                  Text(
                    'Emergency contact: ${contact.name} · ${contact.phone}${contact.relationship == null ? '' : ' · ${contact.relationship}'}',
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push(memberPath(scope, edit: true)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit member'),
                ),
              ],
            ),
            MemberSection(
              title: 'Current membership',
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push(membershipPath(scope)),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Membership & payments'),
                ),
                if (data.currentSubscription == null)
                  const Text('No current membership.')
                else
                  membershipText(data.currentSubscription!),
                if (data.currentPayments
                    case final CurrentMembershipPayments money) ...[
                  Text('Paid: ${formatInrPaise(money.paidPaise)}'),
                  Text('Balance: ${formatInrPaise(money.balancePaise)}'),
                  Text('Successful payments: ${money.count}'),
                ],
              ],
            ),
            MemberSection(
              title: 'Payments',
              children: [
                Text(
                  'Successful total: ${formatInrPaise(data.payments.totalPaise)}',
                ),
                Text('Successful payments: ${data.payments.count}'),
                if (data.payments.latest case final SuccessfulPayment payment)
                  Text(
                    'Latest: ${formatInrPaise(payment.amountPaise)} · ${payment.method}\n${payment.paidAt.toUtc().toIso8601String()} (UTC)',
                  )
                else
                  const Text('No successful payments.'),
              ],
            ),
            MemberSection(
              title: 'Attendance',
              children: [
                Text('Completed visits: ${data.attendance.visits}'),
                Text(
                  data.attendance.checkedIn
                      ? 'Currently checked in'
                      : 'Currently checked out',
                ),
                if (data.attendance.latest case final MemberVisit visit)
                  Text(
                    'Latest visit: ${visit.status}\n${visit.checkInAt.toUtc().toIso8601String()} (UTC)${visit.checkOutAt == null ? '' : '\nChecked out: ${visit.checkOutAt!.toUtc().toIso8601String()} (UTC)'}',
                  )
                else
                  const Text('No attendance yet.'),
              ],
            ),
            MemberSection(
              title: 'Assigned trainers',
              children: [
                if (data.trainers.isEmpty) const Text('No assigned trainers.'),
                ...data.trainers.map(
                  (trainer) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${trainer.name} · ${trainer.code}\n${trainer.phone}',
                    ),
                  ),
                ),
              ],
            ),
            _MembershipHistory(
              request: request,
              onPage: (page) => setState(() => _historyPage = page),
            ),
          ],
        ],
      ),
    );
  }
}

class _MembershipHistory extends ConsumerWidget {
  const _MembershipHistory({required this.request, required this.onPage});
  final HistoryRequest request;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberHistoryProvider(request));
    final history = state.asData?.value;
    return MemberSection(
      title: 'Membership history',
      children: [
        if (state.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (state.hasError)
          MemberError(
            error: state.error,
            retry: () => ref.invalidate(memberHistoryProvider(request)),
          )
        else if (history != null) ...[
          if (history.subscriptions.isEmpty)
            const Text('No memberships on this page.'),
          ...history.subscriptions.map(
            (membership) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  membershipText(membership),
                  if (membership.payments != null)
                    Text(
                      'Paid: ${formatInrPaise(membership.payments!.paidPaise)} · Balance: ${formatInrPaise(membership.payments!.balancePaise)}',
                    ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => MembershipInspection(
                        request: (
                          scope: request.scope,
                          subscriptionId: membership.id,
                        ),
                      ),
                    ),
                    child: const Text('View membership details'),
                  ),
                  const Divider(),
                ],
              ),
            ),
          ),
          PageControls(
            page: history.pagination.page,
            total: history.pagination.total,
            previous: history.pagination.hasPrevious
                ? () => onPage(history.pagination.page - 1)
                : null,
            next: history.pagination.hasNext
                ? () => onPage(history.pagination.page + 1)
                : null,
          ),
        ],
      ],
    );
  }
}

class MembershipInspection extends ConsumerWidget {
  const MembershipInspection({super.key, required this.request});
  final MembershipRequest request;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(membershipDetailProvider(request));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Membership details')),
                IconButton(
                  tooltip: 'Close membership details',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (state.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.hasError)
              MemberError(
                error: state.error,
                retry: () => ref.invalidate(membershipDetailProvider(request)),
              )
            else if (state.asData?.value
                case final MembershipDetail detail) ...[
              membershipText(detail.subscription),
              Text('Paid: ${formatInrPaise(detail.payments.paidPaise)}'),
              Text('Balance: ${formatInrPaise(detail.payments.balancePaise)}'),
              if (detail.subscription.cancelledAt != null)
                Text(
                  'Cancelled: ${detail.subscription.cancelledAt!.toUtc().toIso8601String()} (UTC)',
                ),
              if (detail.subscription.cancellationReason != null)
                Text('Reason: ${detail.subscription.cancellationReason}'),
            ] else
              const Text('This gym context is no longer available.'),
          ],
        ),
      ),
    );
  }
}
