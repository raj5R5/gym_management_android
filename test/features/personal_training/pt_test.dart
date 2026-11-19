import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/personal_training/pt.dart';
import 'package:gym_management_app/features/personal_training/pt_pages.dart';
import 'package:gym_management_app/features/personal_training/pt_widgets.dart';

import 'pt_fakes.dart';

void main() {
  group('PtPackage', () {
    test('admin view carries money; trainer view has none and no due', () {
      final admin = PtPackage.fromJson(ptJson());
      expect(admin.balancePaise, 300000);
      expect(admin.hasDue, isTrue);
      expect(admin.commissionPercent, 12.5);
      expect(admin.payments.single.commissionPaise, 12500);
      final trainer = PtPackage.fromJson(ptJson(money: false));
      expect(trainer.pricePaise, isNull);
      expect(trainer.hasDue, isFalse);
      expect(trainer.payments, isEmpty);
      expect(trainer.canLogSession, isTrue);
    });

    test(
      'sessions can be logged only on active, unexpired packages with sessions left',
      () {
        expect(PtPackage.fromJson(ptJson(used: 4)).canLogSession, isFalse);
        expect(
          PtPackage.fromJson(ptJson(expired: true)).canLogSession,
          isFalse,
        );
        expect(
          PtPackage.fromJson(ptJson(status: 'cancelled')).canLogSession,
          isFalse,
        );
      },
    );

    test('status line and filters', () {
      final active = PtPackage.fromJson(ptJson());
      final owingDone = PtPackage.fromJson(
        ptJson(id: 'b', status: 'completed', used: 4),
      );
      final paidDone = PtPackage.fromJson(
        ptJson(id: 'c', status: 'completed', used: 4, paid: 400000),
      );
      final cancelled = PtPackage.fromJson(
        ptJson(id: 'd', status: 'cancelled'),
      );
      expect(ptStatusLine(active), '3 of 4 sessions left');
      expect(ptStatusLine(owingDone), 'All sessions used');
      expect(ptStatusLine(cancelled), 'Cancelled');
      expect(
        ptStatusLine(PtPackage.fromJson(ptJson(expired: true))),
        'Expired with 3 left',
      );
      final all = [active, owingDone, paidDone, cancelled];
      expect(filterPtPackages(all, PtListFilter.active), [active]);
      // A cancelled package owes nothing more.
      expect(filterPtPackages(all, PtListFilter.due), [active, owingDone]);
      expect(filterPtPackages(all, PtListFilter.completed), [
        owingDone,
        paidDone,
        cancelled,
      ]);
      expect(formatPercent(12.5), '12.5%');
      expect(formatPercent(10), '10%');
    });
  });

  testWidgets(
    'PT page lists packages with dues and shows the commission report',
    (tester) async {
      final repository = FakePtRepository();
      await tester.pumpWidget(ptHarness(repository, const PtPage()));
      await tester.pumpAndSettle();
      expect(find.text('Riya Shah'), findsOneWidget);
      expect(find.text('₹3,000.00 due'), findsOneWidget);
      expect(find.text('3 of 4 sessions left'), findsOneWidget);
      expect(find.text('Active 1'), findsOneWidget);

      await tester.tap(find.text('Commission'));
      await tester.pumpAndSettle();
      expect(find.text('₹375.00'), findsOneWidget);
      expect(find.text('12.5%'), findsOneWidget);
      await tester.tap(find.text('12.5%'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pt-rate')), '15');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['rate:$trainerA:15.0']);
    },
  );

  testWidgets('package detail logs a session and records a payment', (
    tester,
  ) async {
    final repository = FakePtRepository();
    await tester.pumpWidget(
      ptHarness(repository, const PtPackageDetailPage(packageId: pkgA)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Legs'), findsOneWidget);
    await tester.tap(find.text('Log a session'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pt-session-note')),
      'Back',
    );
    await tester.tap(find.text('Log session'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['session:Back']);
    expect(find.text('2 of 4 sessions left'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Record payment'), 100);
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.text('3000'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pt-payment-amount')),
      '5000',
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(find.text('More than the unpaid amount'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pt-payment-amount')),
      '1000',
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'pay:100000:cash');
  });

  testWidgets('a trainer sees sessions without money or cancel', (
    tester,
  ) async {
    final repository = FakePtRepository(packages: [ptJson(money: false)]);
    await tester.pumpWidget(
      ptHarness(repository, const PtPackageDetailPage(packageId: pkgA)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log a session'), findsOneWidget);
    expect(find.text('Price'), findsNothing);
    expect(find.text('Record payment'), findsNothing);
    expect(find.text('Cancel package'), findsNothing);
  });

  testWidgets(
    'selling from a member profile sends the package and first payment',
    (tester) async {
      final repository = FakePtRepository(packages: []);
      final member = PtPerson.fromJson({
        'id': memberA,
        'name': 'Riya Shah',
        'memberCode': 'ME001',
      });
      await tester.pumpWidget(
        ptHarness(repository, SellPtSheet(member: member)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Riya Shah'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pt-trainer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vikram Rao · 12.5% commission').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pt-price')), '6000');
      await tester.enterText(find.byKey(const ValueKey('pt-paid')), '2000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sell package'));
      await tester.tap(find.text('Sell package'));
      await tester.pumpAndSettle();
      expect(repository.calls, [
        'create:$memberA:$trainerA:12:600000:60:200000:cash',
      ]);
    },
  );
}
