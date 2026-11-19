import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/presentation/plan_summary_card.dart';
import 'package:gym_management_app/shared/widgets/titanium_surface.dart';

MembershipPlan plan({
  String id = 'plan-test',
  int days = 90,
  int price = 400000,
  String status = 'active',
  String name = 'Strength Quarterly',
  int? members,
}) => MembershipPlan.fromJson({
  'id': id,
  'gymId': 'gym-test',
  'name': name,
  'durationDays': days,
  'price': price,
  'status': status,
  'description': 'Gym floor and strength training access.',
  'activeMemberCount': ?members,
});

void main() {
  Future<void> pump(
    WidgetTester tester, {
    MembershipPlan? value,
    MembershipPlan? baseline,
    VoidCallback? edit,
    bool dark = true,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: TitaniumCanvas(
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PlanSummaryCard(
                  plan: value ?? plan(),
                  baseline: baseline,
                  onEdit: edit ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('duration words keep the saved day count visible', () {
    for (final sample in [
      (days: 1, words: '1 day'),
      (days: 30, words: '1 month'),
      (days: 31, words: '31 days'),
      (days: 90, words: '3 months'),
      (days: 14, words: '2 weeks'),
      (days: 365, words: '1 year'),
      (days: 730, words: '2 years'),
    ]) {
      test('${sample.days} days → ${sample.words}', () {
        expect(planDurationWords(sample.days), sample.words);
      });
    }
  });

  test('savings compare against the shortest active paid plan', () {
    final monthly = plan(id: 'm', days: 30, price: 150000, name: 'Monthly');
    final quarterly = plan(id: 'q', days: 90, price: 400000);
    final yearly = plan(id: 'y', days: 365, price: 1200000);
    final free = plan(id: 'f', days: 7, price: 0, name: 'Trial');
    final inactive = plan(id: 'i', days: 1, price: 10000, status: 'inactive');
    expect(
      comparisonBaseline([yearly, free, inactive, quarterly, monthly])?.id,
      'm',
    );
    expect(savingsPaise(quarterly, monthly), 50000);
    expect(savingsPaise(yearly, monthly), 625000);
    expect(savingsPaise(monthly, monthly), 0, reason: 'never against itself');
    expect(
      savingsPaise(plan(id: 'x', days: 90, price: 500000), monthly),
      0,
      reason: 'a dearer plan saves nothing',
    );
    expect(perDayPaise(monthly), 5000);
  });

  testWidgets('price, plain duration, exact days, per-day price and members', (
    tester,
  ) async {
    await pump(tester, value: plan(members: 3));
    expect(find.text('Strength Quarterly'), findsOneWidget);
    expect(find.text('₹4,000'), findsOneWidget);
    expect(
      find.text('for 3 months (90 days) · ₹44.44 per day'),
      findsOneWidget,
    );
    expect(find.text('3 members on this plan'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('Saves'), findsNothing);
  });

  testWidgets('savings versus the baseline plan are shown', (tester) async {
    final monthly = plan(id: 'm', days: 30, price: 150000, name: 'Monthly');
    await pump(tester, value: plan(members: 1), baseline: monthly);
    expect(find.text('Saves ₹500 vs Monthly'), findsOneWidget);
    expect(find.text('1 member on this plan'), findsOneWidget);
  });

  testWidgets('member count states: none yet and unavailable', (tester) async {
    await pump(tester, value: plan(members: 0));
    expect(find.text('No members on this plan yet'), findsOneWidget);
    await pump(tester, value: plan());
    expect(find.text('Member count unavailable'), findsOneWidget);
  });

  testWidgets('free plan shows Free without a per-day price', (tester) async {
    await pump(tester, value: plan(days: 7, price: 0, name: 'Trial'));
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('for 1 week (7 days)'), findsOneWidget);
  });

  testWidgets('edit is the only action and is reported once', (tester) async {
    var edits = 0;
    await pump(tester, edit: () => edits++);
    await tester.tap(find.text('Edit plan'));
    await tester.pumpAndSettle();
    expect(edits, 1);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'long inactive plan and large exact price fit 320dp, dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const name =
              'Complete Strength, Conditioning and Personal Training Membership';
          await pump(
            tester,
            dark: dark,
            scale: scale,
            value: plan(
              days: 3650,
              price: 999999999,
              status: 'inactive',
              name: name,
              members: 1234,
            ),
          );
          expect(find.text(name), findsOneWidget);
          expect(find.text('Inactive'), findsOneWidget);
          expect(find.textContaining('(3650 days)'), findsOneWidget);
          await tester.ensureVisible(find.text('₹99,99,999.99'));
          await tester.pumpAndSettle();
          expect(find.text('₹99,99,999.99').hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.text('Edit plan'));
          await tester.pumpAndSettle();
          expect(find.text('Edit plan').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
