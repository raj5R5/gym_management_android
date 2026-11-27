import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/widgets/page_controls.dart';

void main() {
  Future<void> pump(WidgetTester tester, PageControls controls) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: controls)));

  testWidgets('a single page shows no pager', (tester) async {
    await pump(
      tester,
      const PageControls(page: 1, total: 3, previous: null, next: null),
    );
    expect(find.text('Page 1 · 3 total'), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);
  });

  testWidgets('more pages show the pager', (tester) async {
    await pump(
      tester,
      PageControls(page: 1, total: 21, previous: null, next: () {}),
    );
    expect(find.text('Page 1 · 21 total'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);
  });
}
