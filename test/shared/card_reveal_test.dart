import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/card_reveal.dart';

void main() {
  tearDown(CardOrigin.clear);

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 200),
              Builder(
                builder: (context) => SizedBox(
                  width: 200,
                  height: 80,
                  child: InkWell(
                    key: const ValueKey('card'),
                    onTap: () {
                      CardOrigin.mark(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(body: Text('Detail')),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('Plain')),
                    ),
                  ),
                  child: const Text('open plain'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a page opened from a card grows out of it and back', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.tap(find.byKey(const ValueKey('card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CardReveal), findsOneWidget);
    final reveal = tester.widget<CardReveal>(find.byType(CardReveal));
    expect(reveal.origin, const Rect.fromLTWH(0, 200, 200, 80));

    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);

    // Back plays the same reveal in reverse, into the card.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CardReveal), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('a page not opened from a card uses the usual transition', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.tap(find.text('open plain'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CardReveal), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Plain'), findsOneWidget);
  });

  testWidgets('a stale mark is not used by a later page', (tester) async {
    await pumpList(tester);
    CardOrigin.mark(tester.element(find.byKey(const ValueKey('card'))));
    expect(CardOrigin.take(), isNotNull);
    expect(CardOrigin.take(), isNull, reason: 'an origin is used once');
  });
}
