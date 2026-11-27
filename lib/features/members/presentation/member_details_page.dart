import '../photos/member_photo_widgets.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/formatting/payment_date.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../memberships/presentation/billing_components.dart'
    show FinancialRefreshStatus;
import 'member_details_cards.dart';
import 'member_details_activity.dart';
import 'member_details_financial_cards.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import '../../memberships/presentation/billing_components.dart'
    show membershipPath;

// Observe existing state directly so route resumption does not add a second
// asynchronous provider layer. Never format with stale gym metadata on refresh.
final _verifiedGymTimezone = dashboardProvider.select(
  (state) => state.isLoading || state.hasError
      ? null
      : state.asData?.value?.period.timezone,
);

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
  MemberScope? _scope;
  Object? _repository;
  MemberSummary? _snapshot;
  @override
  void didUpdateWidget(MemberDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gymId != widget.gymId ||
        oldWidget.memberId != widget.memberId) {
      _historyPage = 1;
      _snapshot = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final timezone = ref.watch(_verifiedGymTimezone);
    final scope = scopeFor(gym, widget.memberId);
    final repository = ref.watch(memberRepositoryProvider);
    if (_scope != scope || !identical(_repository, repository)) {
      _scope = scope;
      _repository = repository;
      _snapshot = null;
      _historyPage = 1;
    }
    final summary = ref.watch(memberSummaryProvider(scope));
    if (!summary.isLoading &&
        !summary.hasError &&
        summary.asData?.value?.member.id.toLowerCase() ==
            scope.memberId.toLowerCase()) {
      _snapshot = summary.asData!.value;
    }
    final data = _snapshot;
    final verified = !summary.isLoading && !summary.hasError;
    final request = (scope: scope, page: _historyPage);
    Future<void> refresh() async {
      if (ref.read(memberSummaryProvider(scope)).isLoading) return;
      ref.invalidate(memberSummaryProvider(scope));
      ref.invalidate(memberHistoryProvider(request));
      ref.invalidate(memberMembershipsProvider(scope));
      // AsyncValue owns safe failures; completing the gesture doesn't expose them.
      await Future.wait([
        ref
            .read(memberMembershipsProvider(scope).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(memberSummaryProvider(scope).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(memberHistoryProvider(request).future)
            .then<void>((_) {}, onError: (Object _) {}),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth > AppSpacing.contentWidth
            ? (constraints.maxWidth - AppSpacing.contentWidth) / 2 +
                  AppSpacing.lg
            : AppSpacing.lg;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.md,
                horizontalPadding,
                AppSpacing.xl,
              ),
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
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Member details',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh member details',
                      onPressed: summary.isLoading ? null : refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (data != null && (summary.isLoading || summary.hasError))
                  FinancialRefreshStatus(
                    loading: summary.isLoading,
                    error: summary.error,
                    retry: refresh,
                  ),
                if (summary.isLoading && data == null)
                  const Center(child: CircularProgressIndicator())
                else if (summary.hasError && data == null)
                  MemberError(
                    error: summary.error,
                    retry: () => ref.invalidate(memberSummaryProvider(scope)),
                  ),
                if (data != null) ...[
                  MemberProfileCard(
                    key: const ValueKey('member-profile-card'),
                    member: data.member,
                    scope: scope,
                  ),
                  // Where this member stands, in one line, before any detail.
                  MemberStatusLine(scope: scope, summary: data),
                  const SizedBox(height: AppSpacing.lg),
                  MemberPhotoRecoveryPanel(
                    member: data.member,
                    enabled: verified,
                  ),
                  // The one card on this screen: the plan and what is owed.
                  GlassCard(
                    key: const ValueKey('member-money-card'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MemberCurrentMembershipCard(
                          key: const ValueKey('member-current-membership-card'),
                          summary: data,
                          scope: scope,
                          profileVerified: verified,
                        ),
                        const Divider(height: AppSpacing.xxl),
                        MemberPaymentSummaryCard(
                          key: ValueKey((scope, repository)),
                          scope: scope,
                          summary: data,
                          profileVerified: verified,
                          timezone: timezone,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  MemberActivityList(
                    scope: scope,
                    summary: data,
                    timezone: timezone,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  MemberPersonalDetails(member: data.member),
                  MemberSupportCards(summary: data),
                  _MembershipHistory(
                    request: request,
                    onPage: (page) => setState(() => _historyPage = page),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MembershipHistory extends ConsumerStatefulWidget {
  const _MembershipHistory({required this.request, required this.onPage});
  final HistoryRequest request;
  final ValueChanged<int> onPage;
  @override
  ConsumerState<_MembershipHistory> createState() => _MembershipHistoryState();
}

class _MembershipHistoryState extends ConsumerState<_MembershipHistory> {
  HistoryRequest? _request;
  Object? _repository;
  MembershipHistory? _snapshot;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(memberRepositoryProvider);
    if (_request != widget.request || !identical(_repository, repository)) {
      _request = widget.request;
      _repository = repository;
      _snapshot = null;
    }
    final state = ref.watch(memberHistoryProvider(widget.request));
    if (!state.isLoading &&
        !state.hasError &&
        state.asData?.value?.memberId.toLowerCase() ==
            widget.request.scope.memberId.toLowerCase()) {
      _snapshot = state.asData!.value;
    }
    final history = _snapshot;
    final verified = !state.isLoading && !state.hasError;
    void retry() => ref.invalidate(memberHistoryProvider(widget.request));
    final total = history?.pagination.total;
    return MemberDetailsDisclosure(
      title: 'Membership history',
      icon: Icons.history,
      subtitle: total == null
          ? null
          : '$total ${total == 1 ? 'membership' : 'memberships'}',
      children: [
        if (history != null && !verified)
          FinancialRefreshStatus(
            loading: state.isLoading,
            error: state.error,
            retry: retry,
          ),
        if (state.isLoading && history == null)
          const Center(child: CircularProgressIndicator())
        else if (state.hasError && history == null)
          MemberError(error: state.error, retry: retry),
        if (history != null) ...[
          if (history.subscriptions.isEmpty)
            const Text('No memberships on this page.'),
          for (final (index, membership) in history.subscriptions.indexed) ...[
            if (index > 0) const Divider(height: AppSpacing.xl),
            SavedMembershipSummary(membership: membership, compact: true),
            const SizedBox(height: AppSpacing.xs),
            if (membership.payments != null &&
                membership.payments!.paidPaise +
                        membership.payments!.balancePaise ==
                    membership.pricePaise)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          'Paid: ${formatInrPaise(membership.payments!.paidPaise)}   ',
                    ),
                    TextSpan(
                      text:
                          'Due: ${formatInrPaise(membership.payments!.balancePaise)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: membership.payments!.balancePaise > 0
                            ? PendingColors.accentFor(
                                Theme.of(context).brightness,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text('Balance unavailable'),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: !verified
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => MembershipInspection(
                            request: (
                              scope: widget.request.scope,
                              subscriptionId: membership.id,
                            ),
                          ),
                        ),
                  child: const Text('View membership details'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Open membership actions',
                  onPressed: !verified
                      ? null
                      : () => context.push(
                          membershipPath(
                            widget.request.scope,
                            subscriptionId: membership.id,
                          ),
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
          if (history.pagination.total > history.subscriptions.length)
            PageControls(
              page: history.pagination.page,
              total: history.pagination.total,
              previous: verified && history.pagination.hasPrevious
                  ? () => widget.onPage(history.pagination.page - 1)
                  : null,
              next: verified && history.pagination.hasNext
                  ? () => widget.onPage(history.pagination.page + 1)
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
    final gym = ref.watch(adminGymProvider);
    final timezone = matchesScope(gym, request.scope)
        ? ref.watch(_verifiedGymTimezone)
        : null;
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
              SavedMembershipSummary(membership: detail.subscription),
              Text('Paid: ${formatInrPaise(detail.payments.paidPaise)}'),
              Text('Balance: ${formatInrPaise(detail.payments.balancePaise)}'),
              if (detail.subscription.cancelledAt != null)
                Text(
                  'Cancelled: ${formatPaymentDateTime(MaterialLocalizations.of(context), detail.subscription.cancelledAt!, timezone: timezone)}',
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
