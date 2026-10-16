import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../memberships/billing_fakes.dart';

void main() {
  final paidAt = DateTime.utc(2026, 1, 1, 10);
  OnboardingWizardState paymentDraft({int price = 150000}) =>
      const OnboardingWizardState(
            memberCode: 'ME01',
            firstName: 'Alex',
            lastName: 'River',
            phone: '9876543210',
          )
          .next()
          .selectPlan(MembershipPlan.fromJson(planJson()..['price'] = price))
          .next();

  test('payment is optional and skipped payment produces no object', () {
    final draft = paymentDraft();
    expect(draft.paymentValid, isTrue);
    expect(draft.initialPaymentPaise, 0);
    expect(draft.remainingBalancePaise, 150000);
    expect(draft.toInitialPayment(paidAt: paidAt), isNull);
    expect(draft.next().step, OnboardingWizardStep.review);
  });
  test('free plan clears payment fields and requires no payment', () {
    final entered = paymentDraft().copyWith(
      skipInitialPayment: false,
      paymentAmount: '500',
      paymentMethod: PaymentMethod.upi,
      paymentReference: 'UPI-123',
    );
    final free = entered.selectPlan(
      MembershipPlan.fromJson(planJson()..['price'] = 0),
    );
    expect(free.paymentValid, isTrue);
    expect(free.skipInitialPayment, isTrue);
    expect(free.paymentAmount, isEmpty);
    expect(free.paymentMethod, isNull);
    expect(free.paymentReference, isEmpty);
    expect(free.remainingBalancePaise, 0);
    expect(free.toInitialPayment(paidAt: paidAt), isNull);
  });
  for (final input in [
    '',
    '-1',
    '1.234',
    '1,000',
    '1e2',
    'NaN',
    '10000000.01',
  ]) {
    test('invalid amount "$input" blocks review and conversion', () {
      final draft = paymentDraft().copyWith(
        skipInitialPayment: false,
        paymentAmount: input,
      );
      expect(draft.paymentAmountError, isNotNull);
      expect(draft.initialPaymentPaise, isNull);
      expect(draft.remainingBalancePaise, isNull);
      expect(draft.canContinue, isFalse);
      expect(draft.next().step, OnboardingWizardStep.payment);
      expect(
        () => draft.toInitialPayment(paidAt: paidAt),
        throwsFormatException,
      );
    });
  }
  for (final input in ['0', '0.00', ' 0 ']) {
    test('zero "$input" produces no payment even with a stale reference', () {
      final draft = paymentDraft().copyWith(
        skipInitialPayment: false,
        paymentAmount: input,
        paymentMethod: PaymentMethod.upi,
        paymentReference: 'x',
      );
      expect(draft.initialPaymentPaise, 0);
      expect(draft.remainingBalancePaise, 150000);
      expect(draft.paymentValid, isTrue);
      expect(draft.toInitialPayment(paidAt: paidAt), isNull);
    });
  }
  test('partial and full payments use exact integer paise', () {
    final partial = paymentDraft().copyWith(
      skipInitialPayment: false,
      paymentAmount: '500.03',
    );
    expect(partial.initialPaymentPaise, 50003);
    expect(partial.remainingBalancePaise, 99997);
    final payment = partial.toInitialPayment(paidAt: paidAt)!;
    expect(payment.amountPaise, 50003);
    expect(payment.method, PaymentMethod.cash);
    expect(payment.toJson().containsKey('reference'), isFalse);
    final full = partial.copyWith(paymentAmount: '1500');
    expect(full.remainingBalancePaise, 0);
    expect(full.toInitialPayment(paidAt: paidAt)!.amountPaise, 150000);
  });
  test('overpayment is blocked and does not produce a negative balance', () {
    final draft = paymentDraft().copyWith(
      skipInitialPayment: false,
      paymentAmount: '1500.01',
    );
    expect(
      draft.paymentAmountError,
      'Initial payment cannot exceed the plan price.',
    );
    expect(draft.remainingBalancePaise, isNull);
    expect(draft.canContinue, isFalse);
  });
  for (final method in PaymentMethod.values) {
    test(
      '${method.label} uses the existing positive-payment reference rules',
      () {
        final draft = paymentDraft().copyWith(
          skipInitialPayment: false,
          paymentAmount: '100',
          paymentMethod: method,
        );
        expect(draft.paymentValid, !method.requiresReference);
        final valid = draft.copyWith(paymentReference: 'REF-123');
        expect(valid.paymentValid, isTrue);
        expect(valid.toInitialPayment(paidAt: paidAt)!.method, method);
        expect(valid.toInitialPayment(paidAt: paidAt)!.reference, 'REF-123');
        expect(valid.copyWith(paymentReference: 'x').paymentValid, isFalse);
      },
    );
  }
  test('Back and Continue retain raw amount, method, reference and plan', () {
    final draft = paymentDraft().copyWith(
      skipInitialPayment: false,
      paymentAmount: ' 500.03 ',
      paymentMethod: PaymentMethod.bankTransfer,
      paymentReference: ' BANK-123 ',
    );
    final returned = draft.next().previous().previous().next();
    expect(returned.selectedPlan, same(draft.selectedPlan));
    expect(returned.paymentAmount, ' 500.03 ');
    expect(returned.paymentMethod, PaymentMethod.bankTransfer);
    expect(returned.paymentReference, ' BANK-123 ');
    expect(returned.toInitialPayment(paidAt: paidAt)!.reference, 'BANK-123');
  });
  test(
    'skip clears all fields and re-enabling uses a fresh default method',
    () {
      final entered = paymentDraft().copyWith(
        skipInitialPayment: false,
        paymentAmount: '100',
        paymentMethod: PaymentMethod.card,
        paymentReference: 'CARD-123',
      );
      final skipped = entered.copyWith(skipInitialPayment: true);
      expect(skipped.paymentAmount, isEmpty);
      expect(skipped.paymentMethod, isNull);
      expect(skipped.paymentReference, isEmpty);
      expect(skipped.toInitialPayment(paidAt: paidAt), isNull);
      final resumed = skipped.copyWith(skipInitialPayment: false);
      expect(resumed.paymentAmount, isEmpty);
      expect(resumed.paymentReference, isEmpty);
      expect(resumed.paymentMethod, PaymentMethod.cash);
    },
  );
  for (final memberOnly in [false, true]) {
    test(
      '${memberOnly ? 'member-only choice' : 'plan removal'} clears plan and payment',
      () {
        final draft = paymentDraft().copyWith(
          skipInitialPayment: false,
          paymentAmount: '100',
          paymentMethod: PaymentMethod.upi,
          paymentReference: 'UPI-123',
        );
        final cleared = draft.copyWith(
          registerMemberOnly: memberOnly,
          clearSelectedPlan: !memberOnly,
        );
        expect(cleared.selectedPlan, isNull);
        expect(cleared.paymentAmount, isEmpty);
        expect(cleared.paymentReference, isEmpty);
        expect(cleared.paymentMethod, isNull);
        expect(cleared.toInitialPayment(paidAt: paidAt), isNull);
        if (memberOnly) {
          expect(cleared.previous().next().step, OnboardingWizardStep.review);
        }
      },
    );
  }
  test(
    'switching to a cheaper paid plan preserves input and revalidates it',
    () {
      final draft = paymentDraft().copyWith(
        skipInitialPayment: false,
        paymentAmount: '1000',
      );
      final cheaper = draft.selectPlan(
        MembershipPlan.fromJson(
          planJson()
            ..addAll({'id': '000000000000000000000034', 'price': 50000}),
        ),
      );
      expect(cheaper.paymentAmount, '1000');
      expect(
        cheaper.paymentAmountError,
        'Initial payment cannot exceed the plan price.',
      );
      expect(cheaper.next().step, OnboardingWizardStep.payment);
    },
  );
}
