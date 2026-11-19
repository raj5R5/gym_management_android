import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
import '../../admin_dashboard/presentation/revenue_period_label.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../members/providers/member_providers.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import 'payment_transaction_details.dart';
import '../data/payment_repository.dart';

class RevenueDetailsPage extends ConsumerStatefulWidget {
  const RevenueDetailsPage({
    super.key,
    required this.gymId,
    required this.from,
    required this.to,
  });
  final String? gymId, from, to;
  @override
  ConsumerState<RevenueDetailsPage> createState() => _RevenueDetailsPageState();
}

class _RevenueDetailsPageState extends ConsumerState<RevenueDetailsPage> {
  int _page = 1;
  Object? _scope;
  RevenueRequest? _snapshotRequest;
  RevenuePage? _snapshot;
  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    try {
      DashboardQuery.range(
        CalendarDate.parse(widget.from ?? ''),
        CalendarDate.parse(widget.to ?? ''),
      );
    } on FormatException {
      return const Center(
        child: Text(
          'This revenue range is invalid. Return to the dashboard and choose dates.',
        ),
      );
    }
    final scope = (gym, widget.from, widget.to);
    if (_scope != scope) {
      _scope = scope;
      _page = 1;
    }
    final request = (gym: gym, from: widget.from!, to: widget.to!, page: _page);
    final result = ref.watch(revenueDetailsProvider(request));
    if (_snapshotRequest != request) {
      _snapshotRequest = request;
      _snapshot = null;
    }
    if (!result.isLoading && !result.hasError) _snapshot = result.asData?.value;
    final data = _snapshot;
    Future<void> refresh() async {
      if (ref.read(revenueDetailsProvider(request)).isLoading) return;
      ref.invalidate(revenueDetailsProvider(request));
      ref.invalidate(dashboardProvider);
      await ref
          .read(revenueDetailsProvider(request).future)
          .then<void>((_) {}, onError: (Object _) {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to dashboard',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.dashboard),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Revenue Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh revenue',
                onPressed: result.isLoading ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            '${dashboardDateRangeLabel(CalendarDate.parse(widget.from!), CalendarDate.parse(widget.to!))} · Inclusive',
          ),
          const Text('Successful payments only'),
          const SizedBox(height: AppSpacing.lg),
          if (data != null && (result.isLoading || result.hasError))
            FinancialRefreshStatus(
              loading: result.isLoading,
              error: result.error,
              retry: refresh,
            ),
          if (result.isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (result.hasError && data == null)
            BillingError(
              error: result.error,
              retry: () => ref.invalidate(revenueDetailsProvider(request)),
            ),
          if (data != null) ...[
            SoftPanel(
              glass: true,
              tone: AppTone.payment,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.isLoading || result.hasError
                        ? 'Last verified revenue'
                        : 'Successful revenue',
                  ),
                  Text(
                    formatInrPaise(data.amountPaise),
                    key: const ValueKey('revenueTotal'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFamily: AppTypography.bodyFamily,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '${data.count} successful ${data.count == 1 ? 'payment' : 'payments'}',
                  ),
                  IconLabel(
                    'Gym timezone: ${data.period.timezone}',
                    icon: Icons.schedule,
                  ),
                  const Text('The date range follows the gym timezone.'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (data.transactions.isEmpty)
              const Text('No payments during this period.'),
            for (final transaction in data.transactions) ...[
              SoftPanel(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: () => context.push(
                        memberPath(scopeFor(gym, transaction.member.id)),
                      ),
                      child: Text(transaction.member.name),
                    ),
                    IconLabel(
                      'Member code: ${transaction.member.memberCode}',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PaymentTransactionDetails(
                      payment: transaction.payment,
                      timezone: data.period.timezone,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            PageControls(
              page: data.pagination.page,
              total: data.pagination.total,
              previous: data.pagination.hasPrevious
                  ? () => setState(() => _page--)
                  : null,
              next: data.pagination.hasNext
                  ? () => setState(() => _page++)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
