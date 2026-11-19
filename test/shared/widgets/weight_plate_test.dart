import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/iron_hero.dart';
import 'package:gym_management_app/shared/widgets/weight_plate.dart';

Widget preview({
  bool reduced = false,
  bool visible = true,
  bool hero = false,
}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: TickerMode(enabled: visible, child: child!),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: hero
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: IronHero(
                title: 'BACK IN\nCONTROL.',
                eyebrow: 'MuscleDesk',
              ),
            )
          : const WeightPlate(),
    ),
  ),
);

void main() {
  testWidgets('plate autoplays across complete cycles without controls', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('20 KG'), findsNothing); // Decorative, not business data.
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(seconds: 22));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plate suspends offscreen and for reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(preview(visible: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(preview());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(preview(reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byType(IconButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('hero fits a 320dp phone with $scale text scaling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(preview(hero: true, reduced: true));
      await tester.pumpAndSettle();
      expect(find.text('BACK IN\nCONTROL.'), findsOneWidget);
      final plate = tester.getRect(find.byType(WeightPlate));
      expect(plate.left, greaterThanOrEqualTo(0));
      expect(plate.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  }
}
