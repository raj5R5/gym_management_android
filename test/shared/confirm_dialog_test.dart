import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/widgets/confirm_dialog.dart';

void main() {
  Future<bool?> open(WidgetTester tester, String tap) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showConfirmDialog(
              context,
              title: 'Cancel package?',
              message: '3 unused sessions will be dropped.',
              keepLabel: 'Keep package',
              confirmLabel: 'Cancel package',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel package?'), findsOneWidget);
    expect(find.text('3 unused sessions will be dropped.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Keep package'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cancel package'), findsOneWidget);
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('action button confirms', (tester) async {
    expect(await open(tester, 'Cancel package'), isTrue);
  });

  testWidgets('keep button and dismissing do not confirm', (tester) async {
    expect(await open(tester, 'Keep package'), isFalse);
  });
}
