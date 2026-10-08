import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/shared/formatting/inr.dart';
import 'billing_fakes.dart';

void main() {
  test(
    'M12 plan price is integer paise, description nullable, free plan valid',
    () {
      final plan = MembershipPlan.fromJson(planJson());
      expect(plan.pricePaise, 150000);
      expect(plan.durationDays, 30);
      expect(plan.description, isNull);
      expect(MembershipPlan.fromJson(planJson()..['price'] = 0).pricePaise, 0);
    },
  );
  for (final entry in {
    'price': 1.5,
    'durationDays': 0,
    'status': 'unknown',
  }.entries) {
    test(
      'invalid plan ${entry.key} rejected',
      () => expect(
        () => MembershipPlan.fromJson(planJson()..[entry.key] = entry.value),
        throwsFormatException,
      ),
    );
  }
  test(
    'payment preserves exact paise, method, optional reference and recorder',
    () {
      final value = RecordedPayment.fromJson(
        paymentJson()..addAll({
          'amountPaise': 1000000000,
          'paymentMethod': 'bank_transfer',
          'transactionReference': 'REF-001',
        }),
      );
      expect(value.amountPaise, 1000000000);
      expect(value.method, PaymentMethod.bankTransfer);
      expect(value.reference, 'REF-001');
      expect(value.recordedByUserId, isNull);
      expect(formatInrPaise(value.amountPaise), '₹1,00,00,000.00');
    },
  );
  test(
    'fractional payment rejected',
    () => expect(
      () => RecordedPayment.fromJson(paymentJson()..['amountPaise'] = 1.1),
      throwsFormatException,
    ),
  );
  test('M23 cancellation and backend-derived future state are preserved', () {
    final cancelled = Membership.fromJson(
      fullSubscription(cancelled: true)..addAll({
        'cancelledAt': '2026-03-03T12:00:00Z',
        'cancellationReason': 'Requested',
      }),
    );
    expect(cancelled.cancellationReason, 'Requested');
    expect(cancelled.cancelledAt, isNotNull);
    final future = Membership.fromJson(
      fullSubscription()..['isCurrentlyActive'] = false,
    );
    expect(future.status, 'active');
    expect(future.currentlyActive, isFalse);
    expect(future.cancelledAt, isNull);
  });
  test('pagination cap and empty pages use backend counts', () {
    expect(pagination(1, 0).hasNext, isFalse);
    expect(pagination(1, 21).hasNext, isTrue);
    expect(pagination(10000, 999999).hasNext, isFalse);
    expect(() => pagination(0, 1), throwsFormatException);
  });
  for (final entry in {
    '0.01': 1,
    '1500.50': 150050,
    ' 12.3 ': 1230,
    '10000000': 1000000000,
  }.entries) {
    test(
      'decimal input ${entry.key} converts exactly',
      () => expect(parsePaymentRupees(entry.key), entry.value),
    );
  }
  for (final input in [
    '0',
    '-1',
    'NaN',
    'Infinity',
    '1e3',
    '1.001',
    '1,000',
    '10000000.01',
    '',
    '999999999999999999999999999',
  ]) {
    test(
      'unsafe money $input rejected',
      () => expect(() => parsePaymentRupees(input), throwsFormatException),
    );
  }
  for (final method in PaymentMethod.values) {
    test('${method.wireValue} reference validation matches M14', () {
      expect(
        paymentReferenceError(method, ''),
        method.requiresReference ? isNotNull : isNull,
      );
      expect(paymentReferenceError(method, ' REF-001 '), isNull);
      expect(paymentReferenceError(method, '<private>'), isNotNull);
    });
  }
  test('purchase omits server-managed dates and payment when absent', () {
    final json = PurchaseDraft(planId: planId).toJson('member');
    expect(json, {'memberId': 'member', 'planId': planId});
  });
  test('manual payment uses M22 field names and UTC timestamp', () {
    final payment = ManualPayment(
      amountPaise: 1,
      method: PaymentMethod.upi,
      paidAt: DateTime.utc(2020),
      reference: ' REF-001 ',
    );
    expect(payment.toJson(), {
      'enabled': true,
      'amountPaise': 1,
      'method': 'upi',
      'paidAt': '2020-01-01T00:00:00.000Z',
      'reference': 'REF-001',
    });
    expect(
      () => ManualPayment(
        amountPaise: 0,
        method: PaymentMethod.cash,
        paidAt: DateTime.utc(2020),
      ),
      throwsFormatException,
    );
  });
  test(
    'plan drafts allow free prices and serialize only M12 mutable fields',
    () {
      final draft = PlanDraft(
        name: ' Free ',
        durationDays: 3650,
        pricePaise: 0,
        status: 'inactive',
      );
      expect(draft.toJson(editing: false), {
        'name': 'Free',
        'durationDays': 3650,
        'price': 0,
        'status': 'inactive',
      });
      expect(draft.toJson(editing: true)['description'], isNull);
      expect(parsePaymentRupees('0.00', allowZero: true), 0);
      expect(() => parsePaymentRupees('0'), throwsFormatException);
    },
  );
  test('plan description is trimmed and retained while edit can clear it', () {
    final draft = PlanDraft(
      name: 'Monthly',
      description: ' Access ',
      durationDays: 30,
      pricePaise: 150050,
      status: 'active',
    );
    expect(draft.toJson(editing: true)['description'], 'Access');
    expect(
      MembershipPlan.fromJson(planJson()..['status'] = 'inactive').status,
      'inactive',
    );
  });
  for (final duration in [0, 3651]) {
    test(
      'plan duration $duration rejected',
      () => expect(
        () => PlanDraft(
          name: 'Monthly',
          durationDays: duration,
          pricePaise: 0,
          status: 'active',
        ),
        throwsFormatException,
      ),
    );
  }
  test('plan invalid name, description, status and price are rejected', () {
    expect(
      () => PlanDraft(
        name: ' ',
        durationDays: 30,
        pricePaise: 0,
        status: 'active',
      ),
      throwsFormatException,
    );
    expect(
      () => PlanDraft(
        name: 'A',
        description: 'a' * 2001,
        durationDays: 30,
        pricePaise: 0,
        status: 'active',
      ),
      throwsFormatException,
    );
    expect(
      () => PlanDraft(
        name: 'A',
        durationDays: 30,
        pricePaise: -1,
        status: 'active',
      ),
      throwsFormatException,
    );
    expect(
      () => PlanDraft(
        name: 'A',
        durationDays: 30,
        pricePaise: 1000000001,
        status: 'active',
      ),
      throwsFormatException,
    );
    expect(
      () => PlanDraft(
        name: 'A',
        durationDays: 30,
        pricePaise: 0,
        status: 'archived',
      ),
      throwsFormatException,
    );
  });
}
