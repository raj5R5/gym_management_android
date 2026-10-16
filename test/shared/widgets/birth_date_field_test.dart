import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/birth_date_field.dart';

void main() {
  late TextEditingController canonical;
  setUp(() => canonical = TextEditingController(text: '2000-01-02'));
  tearDown(() => canonical.dispose());
  Future<void> mount(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              child: BirthDateField(controller: canonical, enabled: enabled),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('formats the saved calendar date without rewriting it', (
    tester,
  ) async {
    var changes = 0;
    canonical.addListener(() => changes++);
    await mount(tester);
    expect(find.text('Jan 2, 2000'), findsOneWidget);
    expect(canonical.text, '2000-01-02');
    expect(changes, 0);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).readOnly,
      true,
    );
  });
  testWidgets(
    'cancelling the native picker preserves the exact original date',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('dateOfBirth')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(canonical.text, '2000-01-02');
    },
  );
  testWidgets(
    'selecting a date saves calendar components as ISO without timezone shifting',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('dateOfBirth')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(canonical.text, '2000-01-03');
      expect(find.text('Jan 3, 2000'), findsOneWidget);
    },
  );
  testWidgets('explicit clearing preserves an empty optional canonical value', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Clear date of birth'));
    await tester.pumpAndSettle();
    expect(canonical.text, isEmpty);
    expect(find.text('Choose a date'), findsOneWidget);
    final form = tester.state<FormState>(find.byType(Form));
    expect(form.validate(), true);
  });
  testWidgets('disabled form cannot open or clear its saved date', (
    tester,
  ) async {
    await mount(tester, enabled: false);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('dateOfBirth')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(canonical.text, '2000-01-02');
  });
  testWidgets(
    'invalid canonical data remains blocked by the existing validator',
    (tester) async {
      canonical.text = '2000-02-30';
      await mount(tester);
      expect(tester.state<FormState>(find.byType(Form)).validate(), false);
      await tester.pump();
      expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
      expect(canonical.text, '2000-02-30');
    },
  );
  testWidgets(
    'readable date and clear action fit narrow screens with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester);
      expect(find.text('Jan 2, 2000'), findsOneWidget);
      expect(find.byTooltip('Clear date of birth'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
