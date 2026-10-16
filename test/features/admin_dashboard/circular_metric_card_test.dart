import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/circular_metric_card.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact dashboard icons stay full-size and centered, $brightness scale $scale',
        (tester) async {
          const icons = [
            Icons.account_balance_wallet_outlined,
            Icons.people_outline_rounded,
            Icons.card_membership_outlined,
          ];
          await tester.pumpWidget(
            MaterialApp(
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final icon in icons)
                          SizedBox(
                            width: 104,
                            child: CircularMetricCard(
                              title: 'Metric',
                              caption: 'Current',
                              color: DashboardAccents.members,
                              value: 12,
                              icon: icon,
                              layout: MetricCardLayout.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final icon in icons) {
            final glyph = find.byIcon(icon);
            final ring = find.ancestor(
              of: glyph,
              matching: find.byType(MetricRing),
            );
            expect(tester.getSize(glyph), const Size(18, 18));
            expect(tester.getCenter(glyph), tester.getCenter(ring));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    int? value,
    bool money = false,
    bool reduced = false,
    bool accessible = false,
    MetricCardLayout layout = MetricCardLayout.circular,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: CircularMetricCard(
                layout: layout,
                title: money ? 'Total Revenue' : 'Total Members',
                caption: 'Current metric',
                color: DashboardAccents.members,
                value: value,
                money: money,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness pending badge uses a pale red surface and readable warning accent',
      (tester) async {
        final accent = PendingColors.accentFor(brightness);
        final surface = PendingColors.surfaceFor(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            home: Scaffold(
              body: SizedBox(
                width: 220,
                child: CircularMetricCard(
                  title: 'Pending Amount',
                  caption: 'Current membership dues',
                  color: accent,
                  surfaceTint: surface,
                  iconBackground: surface,
                  icon: Icons.account_balance_wallet_outlined,
                  value: 50000,
                  money: true,
                  layout: MetricCardLayout.compact,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('₹500.00'), findsOneWidget);
        expect(
          tester.widget<MetricRing>(find.byType(MetricRing)).color,
          accent,
        );
        expect(tester.widget<Icon>(find.byType(Icon)).color, accent);
        final circle = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where(
              (box) =>
                  box.decoration is BoxDecoration &&
                  (box.decoration as BoxDecoration).shape == BoxShape.circle,
            )
            .single;
        expect((circle.decoration as BoxDecoration).color, surface);
        expect(tester.binding.hasScheduledFrame, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  MetricRing ring(WidgetTester tester) =>
      tester.widget<MetricRing>(find.byType(MetricRing));

  testWidgets('loading is a static placeholder and first data reveals once', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('—'), findsOneWidget);
    expect(ring(tester).reveal, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mount(tester, value: 12);
    await tester.pump(const Duration(milliseconds: 350));
    expect(ring(tester).reveal, greaterThan(0));
    expect(ring(tester).reveal, lessThan(1));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(ring(tester).reveal, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.textContaining('%'), findsNothing);
  });
  testWidgets('updated count animates, unchanged data does not restart', (
    tester,
  ) async {
    await mount(tester, value: 12);
    await tester.pumpAndSettle();
    await mount(tester, value: 24);
    await tester.pump(const Duration(milliseconds: 300));
    final value = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(FittedBox),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(int.parse(value), greaterThan(12));
    expect(int.parse(value), lessThan(24));
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
    await mount(tester, value: 24);
    expect(ring(tester).reveal, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets(
    'money fades exact integer paise including large values without interpolation',
    (tester) async {
      await mount(tester, value: 100001, money: true);
      expect(find.text('₹1,000.01'), findsOneWidget);
      await tester.pumpAndSettle();
      await mount(tester, value: 9007199254740991, money: true);
      await tester.pumpAndSettle();
      expect(find.text('₹9,00,71,99,25,47,409.91'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reduced motion exposes the final value without animation or progress semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, value: 12, reduced: true);
      expect(find.text('12'), findsOneWidget);
      expect(ring(tester).reveal, 1);
      await tester
          .pump(); // Flush the semantics frame, not an animation duration.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        find.bySemanticsLabel('Total Members: 12. Current metric'),
        findsOneWidget,
      );
      await mount(tester, value: 15, reduced: true);
      await tester.pump();
      expect(find.text('15'), findsOneWidget);
      expect(ring(tester).reveal, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'accessible navigation skips motion while zero money remains exact',
    (tester) async {
      await mount(tester, value: 0, money: true, accessible: true);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(ring(tester).reveal, 1);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mount(tester, value: 101, money: true, accessible: true);
      await tester.pump();
      expect(find.text('₹1.01'), findsOneWidget);
      expect(ring(tester).reveal, 1);
    },
  );
  for (final layout in [
    MetricCardLayout.revenueHero,
    MetricCardLayout.compact,
  ]) {
    testWidgets(
      '$layout uses the production finite reveal and reduced-motion path',
      (tester) async {
        await mount(tester, value: 100000, money: true, layout: layout);
        await tester.pump(const Duration(milliseconds: 300));
        expect(ring(tester).reveal, greaterThan(0));
        expect(ring(tester).reveal, lessThan(1));
        expect(find.text('₹1,000.00'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(ring(tester).reveal, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await mount(
          tester,
          value: 300000,
          money: true,
          reduced: true,
          layout: layout,
        );
        await tester.pump();
        expect(find.text('₹3,000.00'), findsOneWidget);
        expect(ring(tester).reveal, 1);
        // Zero-duration switch cleanup may schedule a frame, never a reveal.
        await tester.pumpAndSettle();
        expect(ring(tester).reveal, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  }
}
