import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/formatting/inr.dart';
import '../../auth/data/auth_failure.dart';
import '../models/dashboard_models.dart';
import '../providers/dashboard_providers.dart';
import 'metric_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  Future<void> _refresh(WidgetRef ref) async {
    try {
      await ref.read(dashboardProvider.notifier).reload();
    } on AuthFailure {
      // The provider exposes a safe error state with retry.
    }
  }

  Future<void> _selectPeriod(
    BuildContext context,
    WidgetRef ref,
    GymDashboard? dashboard,
  ) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 30),
      initialDateRange: dashboard == null
          ? null
          : DateTimeRange(
              start: dashboard.period.from.value,
              end: dashboard.period.to.value,
            ),
      helpText: 'Select period (up to 366 inclusive days)',
    );
    if (range == null || !context.mounted) return;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final dashboard = state.asData?.value;
    final query = ref.watch(dashboardQueryProvider);
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Whole gym · All branches'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _selectPeriod(context, ref, dashboard),
                icon: const Icon(Icons.date_range),
                label: const Text('Select period'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(dashboardQueryProvider.notifier).useGymToday(),
                child: const Text('Gym-local today'),
              ),
              IconButton(
                tooltip: 'Refresh dashboard',
                onPressed: state.isLoading ? null : () => _refresh(ref),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (dashboard == null)
            Text(
              query.from == null
                  ? 'Period: gym-local today'
                  : 'Requested period: ${query.from} to ${query.to} · Inclusive',
            ),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading dashboard',
                ),
              ),
            )
          else if (state.hasError) ...[
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              child: Text(
                state.error is AuthFailure
                    ? (state.error! as AuthFailure).message
                    : 'Dashboard could not be loaded. Please try again.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _refresh(ref),
              child: const Text('Retry dashboard'),
            ),
          ] else if (dashboard != null) ...[
            Text(
              '${dashboard.period.from} to ${dashboard.period.to} · Inclusive',
              key: const Key('dashboard-period'),
            ),
            Text('Gym timezone: ${dashboard.period.timezone}'),
            const SizedBox(height: 12),
            const Text(
              'Profile and subscription counts are current. Successful payments and completed visits use the selected period; checked-in members are current.',
            ),
            if (dashboard.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No dashboard activity to show. All metrics are zero.',
                ),
              ),
            const SizedBox(height: 12),
            _profiles('Members', dashboard.members),
            _profiles('Trainers', dashboard.trainers),
            MetricCard(
              title: 'Subscriptions',
              metrics: [
                (
                  label: 'Active now',
                  value: '${dashboard.subscriptions.currentlyActive}',
                ),
                (
                  label: 'Expiring within 7 days',
                  value: '${dashboard.subscriptions.expiringSoon}',
                ),
                (label: 'Expired', value: '${dashboard.subscriptions.expired}'),
              ],
            ),
            MetricCard(
              title: 'Payments / revenue',
              metrics: [
                (
                  label: 'Successful revenue',
                  value: formatInrPaise(
                    dashboard.payments.periodSuccessfulAmountPaise,
                  ),
                ),
                (
                  label: 'Successful payments',
                  value: '${dashboard.payments.periodSuccessfulCount}',
                ),
              ],
            ),
            MetricCard(
              title: 'Attendance',
              metrics: [
                (
                  label: 'Completed visits',
                  value: '${dashboard.attendance.periodVisits}',
                ),
                (
                  label: 'Unique visiting members',
                  value: '${dashboard.attendance.periodUniqueMembers}',
                ),
                (
                  label: 'Checked in now',
                  value: '${dashboard.attendance.currentlyCheckedIn}',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _profiles(String title, ProfileMetrics metrics) => MetricCard(
    title: title,
    metrics: [
      (label: 'Total', value: '${metrics.total}'),
      (label: 'Active', value: '${metrics.active}'),
      (label: 'Inactive', value: '${metrics.inactive}'),
      (label: 'Suspended', value: '${metrics.suspended}'),
    ],
  );
}
