import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'onboarding_fakes.dart';

void main() {
  test(
    'member-only request normalizes existing draft and omits membership',
    () {
      expect(onboardingRequest().toJson(), {
        'member': {
          'memberCode': 'ME01',
          'firstName': 'Alex',
          'lastName': 'River',
          'phone': '9876543210',
        },
      });
    },
  );
  test(
    'supported optional profile fields are preserved without ownership/status',
    () {
      final request = OnboardingRequest(
        member: MemberDraft(
          memberCode: 'ME01',
          firstName: 'Alex',
          lastName: 'River',
          phone: '9876543210',
          dateOfBirth: CalendarDate(2000, 1, 2),
          gender: 'other',
          address: MemberAddress.fromJson({
            'line1': 'One Street',
            'city': 'Pune',
            'countryCode': 'IN',
          }),
          emergencyContact: EmergencyContact.fromJson({
            'name': 'Pat',
            'phone': '9876543211',
          }),
          status: MemberStatus.suspended,
        ),
      );
      expect(request.toJson()['member'], {
        'memberCode': 'ME01',
        'firstName': 'Alex',
        'lastName': 'River',
        'phone': '9876543210',
        'dateOfBirth': '2000-01-02',
        'gender': 'other',
        'address': {'line1': 'One Street', 'city': 'Pune', 'countryCode': 'IN'},
        'emergencyContact': {'name': 'Pat', 'phone': '9876543211'},
      });
    },
  );
  test('omitted start date and payment remain omitted', () {
    final request = OnboardingRequest(
      member: MemberDraft(
        memberCode: 'ME01',
        firstName: 'Alex',
        lastName: 'River',
        phone: '9876543210',
      ),
      membership: OnboardingMembership(planId: onboardingPlanId),
    );
    expect(request.toJson()['membership'], {'planId': onboardingPlanId});
  });
  test(
    'partial payment uses exact nested contract, integers and UTC timestamp',
    () {
      expect(
        onboardingRequest(
          membership: true,
          amount: 40000,
          method: PaymentMethod.upi,
          reference: ' test-ref ',
        ).toJson()['membership'],
        {
          'planId': onboardingPlanId,
          'startDate': '2026-01-01',
          'payment': {
            'method': 'upi',
            'amountPaise': 40000,
            'paidAt': '2026-01-01T10:00:00.000Z',
            'reference': 'test-ref',
          },
        },
      );
    },
  );
  for (final method in PaymentMethod.values) {
    test(
      'supported ${method.wireValue} payment serializes without enabled',
      () {
        final payment = OnboardingPayment(
          method: method,
          amountPaise: 101,
          paidAt: DateTime.utc(2026, 1, 1),
          reference: method.requiresReference ? 'synthetic-ref' : '',
        );
        expect(payment.toJson()['method'], method.wireValue);
        expect(payment.toJson().containsKey('enabled'), isFalse);
      },
    );
  }
  test(
    'new payment timestamps are truncated to UTC milliseconds before freezing',
    () {
      final timestamp = DateTime.parse('2026-01-01T15:30:00.123456+05:30');
      final payment = OnboardingPayment(
        method: PaymentMethod.cash,
        amountPaise: 40000,
        paidAt: timestamp,
      );
      expect(payment.paidAt.isUtc, isTrue);
      expect(payment.paidAt.microsecond, 0);
      expect(payment.toJson()['paidAt'], '2026-01-01T10:00:00.123Z');
      final operation = pendingOperation(
        request: onboardingRequest(
          membership: true,
          amount: 40000,
          paidAt: timestamp,
        ),
      );
      expect(
        operation.request.toJson()['membership']['payment']['paidAt'],
        '2026-01-01T10:00:00.123Z',
      );
      final result = OnboardingResult.fromJson(
        onboardingResultJson(operation.request),
      );
      expect(
        () => result.validateFor(operation.scope.gymId, operation.request),
        returnsNormally,
      );
    },
  );
  test(
    'legacy microsecond requests accept millisecond results without changing frozen data',
    () {
      for (final timestamp in [
        '2026-01-01T10:00:00.000001Z',
        '2026-01-01T10:00:00.123456Z',
        '2026-01-01T15:30:00.999999+05:30',
      ]) {
        final body = onboardingRequest(
          membership: true,
          amount: 40000,
        ).toJson();
        body['membership']['payment']['paidAt'] = timestamp;
        final original = jsonEncode(body);
        final request = OnboardingRequest.fromFrozenJson(original);
        final expected = DateTime.fromMillisecondsSinceEpoch(
          DateTime.parse(timestamp).millisecondsSinceEpoch,
          isUtc: true,
        );
        final result = OnboardingResult.fromJson(onboardingResultJson(request));
        expect(result.payment!.paidAt, expected);
        expect(
          () => result.validateFor(onboardingScope().gymId, request),
          returnsNormally,
        );
        expect(request.frozenJson, original);
        expect(request.toJson()['membership']['payment']['paidAt'], timestamp);
      }
    },
  );
  test(
    'returned timestamps differing by a millisecond still fail validation',
    () {
      final body = onboardingRequest(membership: true, amount: 40000).toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final request = OnboardingRequest.fromFrozenJson(jsonEncode(body));
      for (final returned in [
        '2026-01-01T10:00:00.122Z',
        '2026-01-01T10:00:00.124Z',
      ]) {
        final resultJson = onboardingResultJson(request);
        resultJson['payment']['paidAt'] = returned;
        expect(
          () => OnboardingResult.fromJson(
            resultJson,
          ).validateFor(onboardingScope().gymId, request),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'zero digital payment needs no reference, but still requires method/time',
    () {
      expect(
        onboardingRequest(
          membership: true,
          amount: 0,
          method: PaymentMethod.upi,
        ).toJson()['membership']['payment']['amountPaise'],
        0,
      );
    },
  );
  test('invalid payment amounts, references and future dates fail locally', () {
    for (final amount in [-1, maximumPaymentPaise + 1]) {
      expect(
        () => OnboardingPayment(
          method: PaymentMethod.cash,
          amountPaise: amount,
          paidAt: DateTime.utc(2026, 1, 1),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => OnboardingPayment(
        method: PaymentMethod.upi,
        amountPaise: 1,
        paidAt: DateTime.utc(2026, 1, 1),
      ),
      throwsFormatException,
    );
    expect(
      () => OnboardingPayment(
        method: PaymentMethod.cash,
        amountPaise: 0,
        paidAt: DateTime.utc(2026, 1, 1),
        reference: '!',
      ),
      throwsFormatException,
    );
    expect(
      () => OnboardingMembership(
        planId: onboardingPlanId,
        startDate: CalendarDate(9999, 1, 1),
      ),
      throwsFormatException,
    );
    expect(
      () => OnboardingPayment(
        method: PaymentMethod.cash,
        amountPaise: 1,
        paidAt: DateTime.now().add(const Duration(days: 1)),
      ),
      throwsFormatException,
    );
  });
  for (final field in ['discountPaise', 'gymId', 'password', 'payment']) {
    test('unknown root field $field is rejected', () {
      final json = onboardingRequest().toJson()..[field] = 0;
      expect(
        () => OnboardingRequest.fromFrozenJson(jsonEncode(json)),
        throwsFormatException,
      );
    });
  }
  test('legacy enabled and nested ownership fields are rejected', () {
    final json = onboardingRequest(membership: true, amount: 1).toJson();
    json['membership']['payment']['enabled'] = true;
    expect(
      () => OnboardingRequest.fromFrozenJson(jsonEncode(json)),
      throwsFormatException,
    );
    final member = onboardingRequest().toJson();
    member['member']['userId'] = 'untrusted';
    expect(
      () => OnboardingRequest.fromFrozenJson(jsonEncode(member)),
      throwsFormatException,
    );
    final zero = onboardingRequest(membership: true, amount: 0).toJson();
    zero['membership']['payment']['reference'] = '   ';
    expect(
      () => OnboardingRequest.fromFrozenJson(jsonEncode(zero)),
      throwsFormatException,
    );
  });
  test(
    'frozen request is immutable and preserves optional nulls, offsets and field order',
    () {
      final body = onboardingRequest(membership: true, amount: 1).toJson();
      body['member']['gender'] = null;
      body['membership']['payment']['paidAt'] = '2026-01-01T15:30:00+05:30';
      final raw = jsonEncode(body);
      final request = OnboardingRequest.fromFrozenJson(raw);
      request.toJson()['member']['firstName'] = 'Changed';
      final restored = OnboardingRequest.fromFrozenJson(request.frozenJson);
      expect(restored.frozenJson, raw);
      expect(restored.toJson(), body);
    },
  );
  test('dedicated member-only summaries parse without full-profile fields', () {
    final request = onboardingRequest();
    final result = OnboardingResult.fromJson(onboardingResultJson(request));
    result.validateFor(onboardingScope().gymId, request);
    expect(result.member.memberCode, 'ME01');
    expect(result.subscription, isNull);
    expect(result.payment, isNull);
    expect(result.billing.outstandingBalancePaise, 0);
  });
  for (final amount in [null, 0, 40000, 150000]) {
    test(
      'membership result parses ${amount ?? 'omitted'} initial payment and exact balance',
      () {
        final request = onboardingRequest(membership: true, amount: amount);
        final result = OnboardingResult.fromJson(onboardingResultJson(request));
        result.validateFor(onboardingScope().gymId, request);
        expect(result.subscription!.planName, 'Monthly');
        expect(
          result.payment?.amountPaise,
          amount == null || amount == 0 ? null : amount,
        );
        expect(result.billing.outstandingBalancePaise, 150000 - (amount ?? 0));
      },
    );
  }
  test('free plan parses zero billing and null payment', () {
    final request = onboardingRequest(membership: true, amount: 0);
    final result = OnboardingResult.fromJson(
      onboardingResultJson(request, price: 0),
    );
    expect(result.billing.planPricePaise, 0);
    expect(result.payment, isNull);
  });
  test(
    'billing rejects floats, discounts, overpayments and inconsistent balances',
    () {
      for (final change in [
        {'planPricePaise': 1.5},
        {'discountPaise': 1},
        {'amountReceivedPaise': 150001},
        {'outstandingBalancePaise': 1},
      ]) {
        final json = onboardingResultJson(onboardingRequest(membership: true));
        (json['billing'] as Map).addAll(change);
        expect(() => OnboardingResult.fromJson(json), throwsFormatException);
      }
    },
  );
  test(
    'cross-linked payment mismatch and unknown sensitive response fields fail closed',
    () {
      final request = onboardingRequest(membership: true, amount: 1);
      final json = onboardingResultJson(request);
      json['payment']['subscriptionId'] = onboardingPlanId;
      expect(() => OnboardingResult.fromJson(json), throwsFormatException);
      final unknown = onboardingResultJson(request)
        ..['accessToken'] = 'not-a-token';
      expect(() => OnboardingResult.fromJson(unknown), throwsFormatException);
    },
  );
  test(
    'result must match gym, plan, member, payment and explicit start date',
    () {
      final request = onboardingRequest(membership: true, amount: 1);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['member']['gymId'] = onboardingPlanId,
        (j) => j['member']['memberCode'] = 'ME02',
        (j) => j['subscription']['membershipPlanId'] = onboardingPaymentId,
        (j) => j['subscription']['startDate'] = '2025-12-31',
        (j) => j['payment']['paymentMethod'] = 'other',
      ]) {
        final json = onboardingResultJson(request);
        mutate(json);
        expect(
          () => OnboardingResult.fromJson(
            json,
          ).validateFor(onboardingScope().gymId, request),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'new operation keys are valid, distinct and remain stable on reconstruction',
    () {
      final first = pendingOperation();
      final second = pendingOperation();
      validateOnboardingKey(first.idempotencyKey);
      expect(first.idempotencyKey, isNot(second.idempotencyKey));
      final restored = PendingOnboardingOperation.decode(first.encode());
      expect(restored.sameSubmission(first), isTrue);
      expect(restored.request.frozenJson, first.request.frozenJson);
    },
  );
}
