import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/models/onboarding_correction.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';

import '../memberships/billing_fakes.dart';
import 'onboarding_fakes.dart';

PendingOnboardingOperation rejected(
  OnboardingBackendCode code, {
  OnboardingRequest? request,
  bool uncertain = false,
}) {
  final operation = preparedOperation(request: request);
  return operation.withLedger(
    revision: uncertain ? 3 : 2,
    attempts: [
      if (uncertain)
        OnboardingAttempt(
          number: 1,
          dispatchedAt: DateTime.utc(2026),
          outcome: OnboardingAttemptOutcome.unresolved,
        ),
      OnboardingAttempt(
        number: uncertain ? 2 : 1,
        dispatchedAt: DateTime.utc(2026),
        outcome: code == OnboardingBackendCode.idempotencyKeyConflict
            ? OnboardingAttemptOutcome.conflict
            : OnboardingAttemptOutcome.rejected,
        rejection: OnboardingBackendRejection.tryFrom(
          code.wireValue,
          code.status,
        ),
      ),
    ],
  );
}

OnboardingRequest paymentRequest() {
  final body = onboardingRequest(
    membership: true,
    amount: 50003,
    method: PaymentMethod.upi,
    reference: 'OLD-REF',
  ).toJson();
  (body['membership'] as Map).remove('startDate');
  (body['member'] as Map<String, dynamic>).addAll({
    'dateOfBirth': '2000-01-02',
    'gender': 'female',
  });
  return OnboardingRequest.fromFrozenJson(jsonEncode(body));
}

void main() {
  test('only fully rejected supported v2 history enables correction', () {
    final supported = rejected(OnboardingBackendCode.duplicateMemberCode);
    expect(OnboardingCorrection.supported(supported), isNotNull);
    expect(OnboardingCorrection.supported(pendingOperation()), isNull);
    expect(OnboardingCorrection.supported(preparedOperation()), isNull);
    expect(
      OnboardingCorrection.supported(
        rejected(OnboardingBackendCode.duplicateMemberCode, uncertain: true),
      ),
      isNull,
    );
    expect(
      OnboardingCorrection.supported(
        rejected(OnboardingBackendCode.idempotencyKeyConflict),
      ),
      isNull,
    );
    expect(
      OnboardingCorrection.supported(rejected(OnboardingBackendCode.forbidden)),
      isNull,
    );
    expect(
      OnboardingCorrection.supported(
        rejected(OnboardingBackendCode.onboardingStorageUnavailable),
      ),
      isNull,
    );
  });

  test('legacy confirmation and v2 confirmation never allow correction', () {
    final legacy = pendingOperation();
    final result = OnboardingResult.fromJson(
      onboardingResultJson(legacy.request),
    );
    expect(OnboardingCorrection.supported(legacy.confirmed(result)), isNull);
    final prepared = preparedOperation();
    final confirmed = prepared.withLedger(
      revision: 2,
      attempts: [
        OnboardingAttempt(
          number: 1,
          dispatchedAt: DateTime.utc(2026),
          outcome: OnboardingAttemptOutcome.confirmed,
        ),
      ],
      result: result,
    );
    expect(OnboardingCorrection.supported(confirmed), isNull);
  });

  for (final field in [
    'futureStartDate',
    'branchId',
    'address',
    'emergencyContact',
  ]) {
    test('uneditable $field is preserved and not offered correction', () {
      final body = paymentRequest().toJson();
      switch (field) {
        case 'futureStartDate':
          (body['membership'] as Map)['startDate'] = '2999-01-01';
        case 'branchId':
          (body['member'] as Map)['branchId'] = onboardingPlanId;
        case 'address':
          (body['member'] as Map)['address'] = {
            'line1': 'Test street',
            'city': 'Test city',
            'countryCode': 'IN',
          };
        case 'emergencyContact':
          (body['member'] as Map)['emergencyContact'] = {
            'name': 'Test contact',
            'phone': '9876543210',
          };
      }
      final operation = rejected(
        OnboardingBackendCode.duplicateMemberCode,
        request: OnboardingRequest.fromFrozenJson(jsonEncode(body)),
      );
      final original = operation.encode();
      expect(OnboardingCorrection.supported(operation), isNull);
      expect(operation.encode(), original);
    });
  }

  test(
    'editable values and integer-paise payment survive draft restoration',
    () {
      final operation = rejected(
        OnboardingBackendCode.duplicatePaymentReference,
        request: paymentRequest(),
      );
      final original = operation.encode();
      final correction = OnboardingCorrection.supported(operation)!;
      final draft = correction.draft(MembershipPlan.fromJson(planJson()));
      expect(draft.step, OnboardingWizardStep.payment);
      expect(draft.memberCode, 'ME01');
      expect(draft.firstName, 'Alex');
      expect(draft.phone, '9876543210');
      expect(draft.dateOfBirth, '2000-01-02');
      expect(draft.gender, 'female');
      expect(draft.paymentAmount, '500.03');
      expect(draft.initialPaymentPaise, 50003);
      expect(draft.paymentMethod, PaymentMethod.upi);
      expect(draft.paymentReference, 'OLD-REF');
      expect(correction.issue(draft)?.step, OnboardingWizardStep.payment);
      expect(
        correction.issue(draft.copyWith(paymentReference: 'NEW-REF')),
        isNull,
      );
      expect(
        correction.issue(draft.copyWith(skipInitialPayment: true)),
        isNull,
      );
      expect(
        correction.issue(draft.copyWith(registerMemberOnly: true)),
        isNull,
      );
      expect(operation.encode(), original);
    },
  );

  test('duplicate code must change after trim and uppercase normalization', () {
    final correction = OnboardingCorrection.supported(
      rejected(OnboardingBackendCode.duplicateMemberCode),
    )!;
    final draft = correction.draft(null);
    expect(correction.issue(draft.copyWith(memberCode: ' me01 ')), isNotNull);
    expect(correction.issue(draft.copyWith(memberCode: 'ME02')), isNull);
    expect(draft.registerMemberOnly, isTrue);
  });

  test('unavailable plan directs to selection and preserves member values', () {
    final correction = OnboardingCorrection.supported(
      rejected(OnboardingBackendCode.planNotFound, request: paymentRequest()),
    )!;
    final draft = correction.draft(null);
    expect(draft.step, OnboardingWizardStep.membershipPlan);
    expect(draft.firstName, 'Alex');
    expect(draft.registerMemberOnly, isFalse);
    expect(draft.selectedPlan, isNull);
    expect(draft.canContinue, isFalse);
  });

  test(
    'current free plan clears initial payment without floating point arithmetic',
    () {
      final correction = OnboardingCorrection.supported(
        rejected(
          OnboardingBackendCode.paymentOverpayment,
          request: paymentRequest(),
        ),
      )!;
      final draft = correction.draft(
        MembershipPlan.fromJson(planJson()..['price'] = 0),
      );
      expect(draft.skipInitialPayment, isTrue);
      expect(draft.initialPaymentPaise, 0);
      expect(draft.paymentAmount, '');
      expect(draft.paymentMethod, isNull);
      expect(draft.paymentReference, '');
    },
  );

  test('an existing member with a past start date can be corrected', () {
    final body = paymentRequest().toJson();
    (body['membership'] as Map)['startDate'] = '2026-01-10';
    final operation = rejected(
      OnboardingBackendCode.validationError,
      request: OnboardingRequest.fromFrozenJson(jsonEncode(body)),
    );
    final correction = OnboardingCorrection.supported(operation);
    expect(correction, isNotNull);
    final draft = correction!.draft(null);
    expect(draft.existingMember, isTrue);
    expect(draft.joinedOn, '2026-01-10');
  });
}
