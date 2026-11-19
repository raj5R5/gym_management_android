import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/widgets/page_section.dart';

void main() {
  testWidgets('rows get a line only between them, starting at the text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeparatedRows(
            indent: 40,
            children: [Text('One'), Text('Two'), Text('Three')],
          ),
        ),
      ),
    );
    final lines = tester.widgetList<Divider>(find.byType(Divider));
    expect(lines, hasLength(2));
    expect(lines.every((line) => line.indent == 40), isTrue);
  });

  testWidgets('a single row has no line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SeparatedRows(children: [Text('Only')])),
      ),
    );
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('a page section is a heading without a card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageSection(title: 'Payments', children: [Text('Row')]),
        ),
      ),
    );
    expect(find.text('Payments'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(
      tester.getSemantics(find.text('Payments')),
      matchesSemantics(label: 'Payments', isHeader: true),
    );
  });
}
