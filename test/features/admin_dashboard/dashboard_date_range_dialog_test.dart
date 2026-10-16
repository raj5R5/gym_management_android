import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/dashboard_date_range_dialog.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool dark = false,
    DateTimeRange? initial,
    ValueChanged<DateTimeRange?>? result,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open calendar'),
              onPressed: () async {
                final selected = await showDialog<DateTimeRange>(
                  context: context,
                  builder: (_) => DashboardDateRangeDialog(
                    initialRange:
                        initial ??
                        DateTimeRange(
                          start: DateTime.utc(2026, 10, 10),
                          end: DateTime.utc(2026, 10, 12),
                        ),
                  ),
                );
                result?.call(selected);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open calendar'));
    await tester.pumpAndSettle();
  }

  Future<void> day(WidgetTester tester, String label) async {
    final finder = find.byKey(ValueKey('calendar-day-$label'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets(
    'calendar endpoints and interior are highlighted; exact inclusive range applies',
    (tester) async {
      final semantics = tester.ensureSemantics();
      DateTimeRange? result;
      await mount(tester, result: (value) => result = value);
      expect(find.byType(TextField), findsNothing);
      await day(tester, '2026-10-10');
      await day(tester, '2026-10-12');
      for (final label in ['2026-10-10', '2026-10-11', '2026-10-12']) {
        final ancestor = find.ancestor(
          of: find.byKey(ValueKey('calendar-day-$label')),
          matching: find.byType(Semantics),
        );
        expect(
          tester
              .widgetList<Semantics>(ancestor)
              .any((widget) => widget.properties.selected == true),
          isTrue,
        );
      }
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result!.start, DateTime.utc(2026, 10, 10));
      expect(result!.end, DateTime.utc(2026, 10, 12));
      semantics.dispose();
    },
  );
  testWidgets('same day can be both endpoints', (tester) async {
    DateTimeRange? result;
    await mount(tester, result: (value) => result = value);
    await day(tester, '2026-10-10');
    await day(tester, '2026-10-10');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.duration, Duration.zero);
  });
  testWidgets('cancel leaves the applied selection untouched', (tester) async {
    DateTimeRange? result;
    await mount(tester, result: (value) => result = value);
    await day(tester, '2026-10-01');
    await day(tester, '2026-10-20');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
  testWidgets('previous/next month and year selection preserve endpoints', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('September 2026'), findsOneWidget);
    await day(tester, '2026-09-30');
    await tester.tap(find.byTooltip('Next month'));
    await tester.pump();
    await day(tester, '2026-10-02');
    expect(find.text('Sep 30, 2026'), findsOneWidget);
    expect(find.text('Oct 2, 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-month')));
    await tester.pumpAndSettle();
    expect(find.byType(YearPicker), findsOneWidget);
    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    expect(find.text('October 2025'), findsOneWidget);
    expect(find.text('Sep 30, 2026'), findsOneWidget);
  });
  testWidgets(
    'reversed and overlong ranges block Apply without changing endpoints',
    (tester) async {
      await mount(tester);
      await day(tester, '2026-10-12');
      await day(tester, '2026-10-10');
      expect(find.text('From must be on or before To.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('calendar-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2027'));
      await tester.pumpAndSettle();
      await day(tester, '2027-10-13');
      expect(
        find.text('Choose no more than 366 inclusive days.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('366 inclusive days is valid, 367 is invalid', (tester) async {
    await mount(
      tester,
      initial: DateTimeRange(
        start: DateTime.utc(2024, 1, 1),
        end: DateTime.utc(2024, 12, 31),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await mount(
      tester,
      initial: DateTimeRange(
        start: DateTime.utc(2024, 1, 1),
        end: DateTime.utc(2025, 1, 1),
      ),
    );
    expect(
      find.text('Choose no more than 366 inclusive days.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
  });
  for (final dark in [false, true]) {
    testWidgets('calendar fits small screens and enlarged text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, dark: dark);
      await day(tester, '2026-10-10');
      await day(tester, '2026-10-12');
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardDateRangeDialog), findsNothing);
    });
  }
}
