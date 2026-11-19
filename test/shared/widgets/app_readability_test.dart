import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/icon_label.dart';
import 'package:gym_management_app/shared/widgets/profile_section.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'financial metadata wraps without loss at 320dp, dark=$dark, scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const amount = 'Outstanding balance: ₹99,99,999.99';
          const reference =
              'Reference: bank-reference-with-a-long-unbroken-identifier-123456789';
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: const ProfileSection(
                      title: 'Saved membership and payment information',
                      icon: Icons.account_balance_wallet_outlined,
                      children: [
                        IconLabel(
                          amount,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        IconLabel(reference, icon: Icons.receipt_long_outlined),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(reference));
          await tester.pumpAndSettle();
          expect(find.text(reference).hitTestable(), findsOneWidget);
          expect(find.text(amount), findsOneWidget);
          expect(tester.takeException(), isNull);
          final semantics = tester.ensureSemantics();
          expect(
            tester.getSemantics(find.text(reference)).label,
            contains(reference),
          );
          semantics.dispose();
        },
      );
    }
  }
}
