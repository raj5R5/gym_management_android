import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';

import '../../auth/data/auth_failure.dart';
import '../models/dashboard_models.dart';
import '../providers/dashboard_providers.dart';
import '../../memberships/data/billing_failure.dart';
import '../../memberships/providers/plan_providers.dart';
import 'circular_metric_card.dart';
import 'dashboard_widgets.dart';
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
  int? _lastPlanCount;

  Future<void> _refresh() async {
    try {
      ref.invalidate(activePlanCountProvider);
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
      _lastPlanCount = null;
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
      _lastPlanCount = null;
    }
    if (!state.isLoading && !state.hasError) {
      _lastDashboard = state.asData?.value;
    }
    if (!plans.isLoading && !plans.hasError && !accessDenied) {
      _lastPlanCount = plans.asData?.value;
    }
    final dashboard = _lastDashboard;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: LayoutBuilder(
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
                Text(
                  'Revenue uses the selected period. Pending dues are current balances across non-cancelled memberships, after all successful payments. Plans are gym-wide.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!state.isLoading &&
                    dashboard?.isEmpty == true &&
                    plans.asData?.value == 0) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const DashboardFeedbackPanel(
                    title: 'Your gym story starts here',
                    message:
                        'No dashboard activity to show. All metrics are zero.',
                  ),
                ],
                if (gym != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  DashboardQuickActions(
                    addMember: () => context.push(
                      '${AppRoutes.members}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
                    ),
                    viewMembers: () => context.go(AppRoutes.members),
                    viewTrainers: () => context.go(AppRoutes.trainers),
                    viewPlans: () => context.go(AppRoutes.plans),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _metricGrid(
    BuildContext context,
    AdminGymContext? gym,
    GymDashboard? data,
    bool unavailableData,
    AsyncValue<int?> plans,
  ) {
    final count = plans.hasError ? null : _lastPlanCount;
    final unavailable = unavailableData
        ? 'Unavailable · Retry dashboard'
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 312 &&
                MediaQuery.textScalerOf(context).scale(16) <= 20
            ? 3
            : constraints.maxWidth >= 328 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        final cards = [
          CircularMetricCard(
            key: ValueKey((gym, 'revenue')),
            title: 'Total Revenue',
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
            title: 'Pending Amount',
            layout: MetricCardLayout.compact,
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
            key: ValueKey((gym, 'members')),
            title: 'Total Members',
            layout: MetricCardLayout.compact,
            caption: 'Current member profiles',
            onTap: gym == null ? null : () => context.go(AppRoutes.members),
            periodLabel: 'CURRENT PROFILES',
            icon: Icons.people_outline_rounded,
            value: data?.members.total,
            color: DashboardAccents.membersFor(Theme.of(context).brightness),
            error: unavailable,
          ),
          CircularMetricCard(
            key: ValueKey((gym, 'plans')),
            title: 'Active Plans',
            layout: MetricCardLayout.compact,
            caption: 'Active membership plans',
            onTap: gym == null
                ? null
                : () => context.go('${AppRoutes.plans}?status=active'),
            periodLabel: 'GYM-WIDE PLANS',
            icon: Icons.card_membership_outlined,
            value: count,
            color: DashboardAccents.revenueFor(Theme.of(context).brightness),
            error: plans.hasError
                ? (plans.error is BillingFailure
                      ? (plans.error! as BillingFailure).message
                      : 'Plans could not be loaded.')
                : null,
            retry: plans.hasError
                ? () => ref.invalidate(activePlanCountProvider)
                : null,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards.first,
            const SizedBox(height: AppSpacing.md),
            for (var start = 1; start < cards.length; start += columns) ...[
              if (start > 1) const SizedBox(height: AppSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = start;
                      i < cards.length && i < start + columns;
                      i++
                    ) ...[
                      if (i > start) const SizedBox(width: AppSpacing.sm),
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
