import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/presentation/member_components.dart';
import 'package:gym_management_app/features/members/presentation/member_details_cards.dart';
import 'package:gym_management_app/features/members/presentation/member_details_page.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/models/membership_eligibility.dart';
import 'package:gym_management_app/shared/widgets/membership_date_range.dart';

import '../admin_dashboard/dashboard_fakes.dart'
    show gymA, dashboardJson, FakeDashboardRepository;
import 'member_fakes.dart';

const _gym = (userId: 'synthetic-owner', gymId: gymA);
const _scope = (userId: 'synthetic-owner', gymId: gymA, memberId: memberId);

class _FixedGym extends AdminGymController {
  @override
  AdminGymContext build() => _gym;
}

void main() {
  Membership membership({bool cancelled = false}) => Membership.fromJson(
    subscriptionJson(cancelled: cancelled)..addAll({
      'startDate': '2026-03-08',
      'endDate': '2026-03-09',
      'durationDaysSnapshot': 1,
    }),
  );

  Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  test('calendar parsing and picker preserve labels, not UTC instants', () {
    final start = CalendarDate.parse('2026-03-08');
    final end = CalendarDate.parse('2026-03-09');
    expect(start.toString(), '2026-03-08');
    expect(end.value.difference(start.value).inDays, 1);
    expect(start.value.isUtc, isTrue);
    expect(
      CalendarDate.fromPicker(DateTime(2026, 3, 8, 23, 30)).toString(),
      '2026-03-08',
    );
  });

  test(
    'lifecycle and eligibility use server status rather than phone today',
    () {
      final upcoming = Membership.fromJson(
        subscriptionJson()..addAll({
          'startDate': '2099-03-08',
          'endDate': '2099-03-09',
          'durationDaysSnapshot': 1,
          'status': 'active',
          'isCurrentlyActive': false,
        }),
      );
      expect(blockingMembership([upcoming]), same(upcoming));
      expect(upcoming.currentlyActive, isFalse);
      final expired = Membership.fromJson(
        subscriptionJson()
          ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
      );
      expect(blockingMembership([expired]), isNull);
    },
  );

  for (final variant in ['billing', 'current', 'history', 'inspection']) {
    testWidgets('$variant keeps DST-boundary dates and gym calendar wording', (
      tester,
    ) async {
      final record = membership();
      await mount(
        tester,
        variant == 'billing'
            ? membershipText(record)
            : SavedMembershipSummary(
                membership: record,
                compact: variant == 'history',
                emphasizeDuration: variant == 'current',
              ),
      );
      expect(find.textContaining('gym timezone'), findsOneWidget);
      expect(find.textContaining('UTC calendar'), findsNothing);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '8 Mar 2026 – 9 Mar 2026',
      );
      final rangeSemantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(MembershipDateRange),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        rangeSemantics.properties.label,
        contains('End date is exclusive'),
      );
      expect(record.startDate.toString(), '2026-03-08');
      expect(record.endDate.toString(), '2026-03-09');
      expect(tester.takeException(), isNull);
    });
  }

  for (final zone in ['Asia/Kolkata', 'UTC', null]) {
    final expected = zone == 'Asia/Kolkata'
        ? 'Mar 2, 2026 · 2:00 AM · Asia/Kolkata'
        : zone == 'UTC'
        ? 'Mar 1, 2026 · 8:30 PM · UTC'
        : 'Mar 1, 2026 · 8:30 PM · UTC (gym timezone unavailable)';

    testWidgets('latest payment uses $zone and preserves the saved instant', (
      tester,
    ) async {
      final payments = MemberPaymentSummary.fromJson({
        'totalSuccessfulAmountPaise': 100,
        'successfulPaymentCount': 1,
        'latestSuccessfulPayment': {
          'id': '000000000000000000000055',
          'subscriptionId': subscriptionId,
          'amountPaise': 100,
          'paymentMethod': 'cash',
          'paidAt': '2026-03-01T20:30:00.000Z',
        },
      });
      await mount(
        tester,
        MemberLatestPayment(payments: payments, timezone: zone),
      );
      expect(find.textContaining(expected), findsOneWidget);
      expect(
        payments.latest!.paidAt.toIso8601String(),
        '2026-03-01T20:30:00.000Z',
      );
    });

    testWidgets(
      'cancellation inspection uses $zone with explicit UTC fallback',
      (tester) async {
        final request = (scope: _scope, subscriptionId: subscriptionId);
        final detail = MembershipDetail.fromJson({
          'subscription': subscriptionJson(cancelled: true)
            ..['cancelledAt'] = '2026-03-01T20:30:00.000Z',
          'paymentSummary': {
            'totalSuccessfulPaidPaise': 0,
            'remainingBalancePaise': 150000,
          },
        });
        final dashboard = FakeDashboardRepository();
        if (zone == null) {
          dashboard.failure = StateError('Gym timezone unavailable');
        } else {
          final json = dashboardJson();
          (json['period'] as Map)['timezone'] = zone;
          dashboard.result = GymDashboard.fromJson(json);
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminGymProvider.overrideWith(_FixedGym.new),
              dashboardRepositoryProvider.overrideWithValue(dashboard),
              membershipDetailProvider(
                request,
              ).overrideWith((ref) async => detail),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(body: MembershipInspection(request: request)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancelled: $expected'), findsOneWidget);
        expect(
          detail.subscription.cancelledAt!.toIso8601String(),
          '2026-03-01T20:30:00.000Z',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
