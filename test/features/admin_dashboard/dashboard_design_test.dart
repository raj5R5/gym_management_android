import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/dashboard_widgets.dart';

void main() {
  testWidgets(
    'status summary represents the actual counts and exposes accessible labels',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: ProfileStatusSummary(
                  metrics: ProfileMetrics.fromJson({
                    'total': 12,
                    'active': 9,
                    'inactive': 2,
                    'suspended': 1,
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      final boxes = find.descendant(
        of: find.byType(ProfileStatusSummary),
        matching: find.byType(ColoredBox),
      );
      expect(tester.getSize(boxes.at(0)).width, 180);
      expect(tester.getSize(boxes.at(1)).width, 40);
      expect(tester.getSize(boxes.at(2)).width, 20);
      expect(tester.widget<ColoredBox>(boxes.at(0)).color, AppPalette.mint);
      expect(
        tester.widget<ColoredBox>(boxes.at(1)).color,
        AppPalette.mutedGrey,
      );
      expect(tester.widget<ColoredBox>(boxes.at(2)).color, AppPalette.coral);
      expect(
        find.bySemanticsLabel(
          'Current status distribution: 9 active, 2 inactive, 1 suspended',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
  testWidgets('zero profile counts never produce a fabricated distribution', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileStatusSummary(
          metrics: ProfileMetrics.fromJson({
            'total': 0,
            'active': 0,
            'inactive': 0,
            'suspended': 0,
          }),
        ),
      ),
    );
    expect(find.byType(Expanded), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ProfileStatusSummary),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });
}
