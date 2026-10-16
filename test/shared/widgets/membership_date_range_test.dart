import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/membership_date_range.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    double width = 340,
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool singleLine = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MembershipDateRange(
                singleLine: singleLine,
                start: DateTime.utc(2026, 10, 12),
                end: DateTime.utc(2026, 12, 12),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  testWidgets('saved calendar range renders compactly on one line', (
    tester,
  ) async {
    await mount(tester);
    final first = find.text('12 Oct 2026 –');
    final last = find.text('12 Dec 2026');
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
    expect(tester.widget<Text>(first).style!.fontSize, 12);
    expect(tester.widget<Text>(first).maxLines, isNull);
    expect(
      tester
          .widget<MembershipDateRange>(find.byType(MembershipDateRange))
          .label,
      '12 Oct 2026 – 12 Dec 2026',
    );
    expect(find.textContaining('Starts'), findsNothing);
    expect(find.textContaining('Ends'), findsNothing);
  });
  testWidgets('narrow range wraps full dates without truncation', (
    tester,
  ) async {
    await mount(tester, width: 180);
    expect(
      tester.getTopLeft(find.text('12 Dec 2026')).dy,
      greaterThan(tester.getTopLeft(find.text('12 Oct 2026 –')).dy),
    );
    expect(
      tester.widget<Text>(find.text('12 Dec 2026')).overflow,
      isNot(TextOverflow.ellipsis),
    );
    expect(tester.takeException(), isNull);
  });
  for (final brightness in Brightness.values) {
    testWidgets('card dates stay complete on one line in $brightness', (
      tester,
    ) async {
      await mount(tester, width: 134, brightness: brightness, singleLine: true);
      final text = tester.widget<Text>(find.text('12 Oct 2026 – 12 Dec 2026'));
      expect(text.maxLines, 1);
      expect(text.softWrap, false);
      expect(text.style!.fontSize, 10);
      expect(
        tester.getSize(find.byType(MembershipDateRange)).height,
        lessThan(20),
      );
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(MembershipDateRange),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, contains('12 Oct 2026 – 12 Dec 2026'));
      expect(semantics.properties.label, contains('End date is exclusive'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text keeps both dates readable in $brightness', (
      tester,
    ) async {
      await mount(tester, scale: 2, brightness: brightness);
      final label = tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(MembershipDateRange),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label;
      expect(label, contains('12 Oct 2026 – 12 Dec 2026'));
      expect(label, contains('End date is exclusive'));
      expect(
        tester.getSize(find.byType(MembershipDateRange)).height,
        greaterThan(24),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
