import 'package:flutter/material.dart';
import '../../../shared/formatting/inr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';

import '../../auth/data/auth_failure.dart';
import '../models/dashboard_models.dart';
import '../providers/dashboard_providers.dart';
import '../../memberships/providers/plan_providers.dart';
import 'circular_metric_card.dart';
import 'dashboard_widgets.dart';
import 'dashboard_home_widgets.dart';
import '../../gym_settings/gym_settings.dart';
import '../../members/models/member_overview.dart';
import '../../members/providers/member_overview_providers.dart';
import '../../member_app/payment_claims.dart';
import 'dashboard_date_range_dialog.dart';
import 'revenue_period_label.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Object? _displayScope;
  GymDashboard? _lastDashboard;

  Future<void> _refresh() async {
    try {
      ref.invalidate(activePlanCountProvider);
      ref.invalidate(memberOverviewProvider);
      ref.invalidate(gymSettingsProvider);
      await Future.wait([
        ref.read(dashboardProvider.notifier).reload(),
        ref.read(activePlanCountProvider.future),
      ]);
    } catch (_) {
      // Both providers expose sanitized errors with explicit retry in the UI.
    }
  }

  Future<void> _selectPeriod(
    BuildContext context,
    GymDashboard? dashboard,
  ) async {
    final scope = ref.read(adminGymProvider);
    final repository = ref.read(dashboardRepositoryProvider);
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => DashboardDateRangeDialog(
        initialRange: dashboard == null
            ? null
            : DateTimeRange(
                start: dashboard.period.from.value,
                end: dashboard.period.to.value,
              ),
      ),
    );
    if (range == null ||
        !context.mounted ||
        !mounted ||
        scope != ref.read(adminGymProvider) ||
        !identical(repository, ref.read(dashboardRepositoryProvider))) {
      return;
    }
    try {
      ref
          .read(dashboardQueryProvider.notifier)
          .selectRange(
            CalendarDate.fromPicker(range.start),
            CalendarDate.fromPicker(range.end),
          );
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose an inclusive range of 1 to 366 days.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final query = ref.watch(dashboardQueryProvider);
    final gym = ref.watch(adminGymProvider);
    final plans = ref.watch(activePlanCountProvider);
    final repository = ref.watch(dashboardRepositoryProvider);
    // Presentation cache only: never share a display across accounts, gyms,
    // API clients or filters. Riverpod still owns all request/result ordering.
    final displayScope = (gym, repository, query.toParameters().toString());
    if (_displayScope != displayScope) {
      _displayScope = displayScope;
      _lastDashboard = null;
    }
    final accessDenied =
        state.error is AuthFailure &&
        {
          AuthFailureKind.forbidden,
          AuthFailureKind.invalidSession,
          AuthFailureKind.invalidCredentials,
        }.contains((state.error! as AuthFailure).kind);
    if (accessDenied) {
      _lastDashboard = null;
    }
    if (!state.isLoading && !state.hasError) {
      _lastDashboard = state.asData?.value;
    }
    final dashboard = _lastDashboard;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth > AppSpacing.contentWidth
            ? (constraints.maxWidth - AppSpacing.contentWidth) / 2 +
                  AppSpacing.lg
            : AppSpacing.lg;
        final compact = constraints.maxHeight < 720;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              compact ? AppSpacing.sm : AppSpacing.md,
              horizontal,
              AppSpacing.lg,
            ),
            children: [
              const DashboardGreeting(),
              const SizedBox(height: AppSpacing.lg),
              if (gym != null) SetupChecklist(gym: gym, dashboard: dashboard),
              const PendingClaimsBanner(),
              DashboardHeader(
                period: dashboard != null
                    ? '${dashboardDateRangeLabel(dashboard.period.from, dashboard.period.to)} · Inclusive'
                    : query.filter != DashboardDateFilter.customRange
                    ? 'Loading selected revenue dates…'
                    : 'Requested period: ${query.from} to ${query.to} · Inclusive',
                timezone: dashboard?.period.timezone,
                filter: query.filter,
                selectPeriod: () => _selectPeriod(context, dashboard),
                selectPreset: (filter) => ref
                    .read(dashboardQueryProvider.notifier)
                    .selectPreset(filter),
                refresh: state.isLoading || plans.isLoading ? null : _refresh,
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.isLoading)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    dashboard == null
                        ? 'Loading your gym overview…'
                        : 'Updating your gym overview…',
                  ),
                )
              else if (state.hasError) ...[
                DashboardFeedbackPanel(
                  icon: Icons.cloud_off_outlined,
                  title: dashboard == null
                      ? 'Unable to load your dashboard'
                      : 'Refresh failed · Showing last successful data',
                  message: state.error is AuthFailure
                      ? (state.error! as AuthFailure).message
                      : 'Dashboard could not be loaded. Please try again.',
                  action: FilledButton(
                    onPressed: _refresh,
                    child: const Text('Retry dashboard'),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _metricGrid(
                context,
                gym,
                dashboard,
                state.hasError && dashboard == null,
                plans,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (gym != null) ...[
                DashboardQuickActions(
                  checkIn: () => context.push(AppRoutes.checkIn),
                  addMember: () => context.push(
                    '${AppRoutes.members}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
                  ),
                  collectDues: () => openMembersFiltered(
                    context,
                    ref,
                    MemberOverviewFilter.dues,
                  ),
                  renewals: () => openMembersFiltered(
                    context,
                    ref,
                    MemberOverviewFilter.expired,
                  ),
                  viewPlans: () => context.go(AppRoutes.plans),
                ),
                const SizedBox(height: AppSpacing.xl),
                DashboardTodo(gym: gym),
                if (dashboard != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline, size: 20),
                    title: const Text('About these figures'),
                    childrenPadding: const EdgeInsets.only(
                      bottom: AppSpacing.lg,
                    ),
                    children: [
                      Text(
                        'Revenue: ${dashboardDateRangeLabel(dashboard.period.from, dashboard.period.to)} · Inclusive\nGym timezone: ${dashboard.period.timezone}\nRevenue includes successful payments only. Outstanding dues are current non-cancelled membership balances, independent of the revenue period. Membership and plan counts are current snapshots.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _metricGrid(
    BuildContext context,
    AdminGymContext? gym,
    GymDashboard? data,
    bool unavailableData,
    AsyncValue<int?> plans,
  ) {
    final unavailable = unavailableData
        ? 'Unavailable · Retry dashboard'
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 312 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        final cards = [
          CircularMetricCard(
            key: ValueKey((gym, 'revenue')),
            title: 'Money collected',
            layout: MetricCardLayout.revenueHero,
            onTap: gym == null || data == null
                ? null
                : () => context.push(
                    Uri(
                      path: AppRoutes.revenue,
                      queryParameters: {
                        'gymId': gym.gymId,
                        'from': data.period.from.toString(),
                        'to': data.period.to.toString(),
                      },
                    ).toString(),
                  ),
            caption:
                data?.payments.periodSuccessfulCount == 0 &&
                    data?.payments.periodSuccessfulAmountPaise == 0
                ? 'No payments during this period'
                : 'Successful payments only',
            money: true,
            icon: Icons.currency_rupee_rounded,
            surfaceTint: AppPalette.peach,
            periodLabel: data == null
                ? null
                : (ref.read(dashboardQueryProvider).filter ==
                              DashboardDateFilter.thisMonth
                          ? 'THIS '
                          : '') +
                      revenuePeriodLabel(
                        data.period,
                        gymToday:
                            ref.read(dashboardQueryProvider).filter ==
                            DashboardDateFilter.today,
                      ),
            value: data?.payments.periodSuccessfulAmountPaise,
            color: DashboardAccents.revenueFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'dues')),
            title: 'Pending dues',
            layout: MetricCardLayout.balance,
            caption: 'Current membership dues',
            onTap: gym == null
                ? null
                : () => context.push(
                    Uri(
                      path: AppRoutes.outstandingDues,
                      queryParameters: {'gymId': gym.gymId},
                    ).toString(),
                  ),
            periodLabel: 'CURRENT BALANCE',
            icon: Icons.account_balance_wallet_outlined,
            surfaceTint: PendingColors.surfaceFor(Theme.of(context).brightness),
            iconBackground: PendingColors.surfaceFor(
              Theme.of(context).brightness,
            ),
            money: true,
            value: data?.payments.outstandingAmountPaise,
            color: DashboardAccents.pendingFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'profit')),
            // A loss shows as a positive amount under the title "Loss".
            title: (data?.expenses?.profitPaise ?? 0) < 0 ? 'Loss' : 'Profit',
            layout: MetricCardLayout.compact,
            caption: data?.expenses == null
                ? 'Collected minus expenses'
                : 'Spent ${formatCompactInrPaise(data!.expenses!.periodAmountPaise)}',
            onTap: gym == null ? null : () => context.push(AppRoutes.expenses),
            periodLabel: 'SELECTED DATES',
            icon: Icons.trending_up_rounded,
            money: true,
            value: data?.expenses?.profitPaise.abs(),
            color: (data?.expenses?.profitPaise ?? 0) < 0
                ? DashboardAccents.pendingFor(Theme.of(context).brightness)
                : DashboardAccents.revenueFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'members')),
            title: 'Active members',
            layout: MetricCardLayout.compact,
            caption: data == null
                ? 'With a current membership'
                : 'of ${data.members.total} members',
            onTap: gym == null
                ? null
                : () => openMembersFiltered(
                    context,
                    ref,
                    MemberOverviewFilter.active,
                  ),
            periodLabel: 'RIGHT NOW',
            icon: Icons.people_outline_rounded,
            value: data?.subscriptions.currentlyActive,
            color: DashboardAccents.membersFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'visits')),
            title: 'Check-ins',
            layout: MetricCardLayout.compact,
            caption: data?.visits == null
                ? 'Visits in this period'
                : '${data!.visits!.distinctMembers} members · ${data.visits!.today} today',
            onTap: gym == null
                ? null
                : () => context.push(AppRoutes.todayVisits),
            periodLabel: 'SELECTED DATES',
            icon: Icons.how_to_reg_outlined,
            value: data?.visits?.periodCount,
            color: DashboardAccents.membersFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'joined')),
            title: 'New members',
            layout: MetricCardLayout.compact,
            caption: 'Joined in this period',
            onTap: gym == null ? null : () => context.go(AppRoutes.members),
            periodLabel: 'SELECTED DATES',
            icon: Icons.person_add_alt_1_outlined,
            value: data?.members.joinedInPeriod,
            color: DashboardAccents.revenueFor(Theme.of(context).brightness),
            error: unavailable,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards.first,
            const SizedBox(height: AppSpacing.md),
            cards[1],
            const SizedBox(height: AppSpacing.md),
            for (var start = 2; start < cards.length; start += columns) ...[
              if (start > 2) const SizedBox(height: AppSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < cards.length && i < start + columns;
                      i++
                    ) ...[
                      if (i > start) const SizedBox(width: AppSpacing.md),
                      SizedBox(width: width, child: cards[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
