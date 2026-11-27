import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart' show gymA;
import '../memberships/billing_fakes.dart';

void main() {
  const valid = OnboardingWizardState(
    memberCode: ' me_01 ',
    firstName: ' Alex ',
    lastName: ' River ',
    phone: '9876543210',
  );
  test('invalid member details cannot advance', () {
    const empty = OnboardingWizardState();
    expect(empty.next().step, OnboardingWizardStep.memberDetails);
    expect(
      valid.copyWith(phone: '123').next().step,
      OnboardingWizardStep.memberDetails,
    );
    expect(
      valid.copyWith(dateOfBirth: '2026-02-30').memberDetailsValid,
      isFalse,
    );
    expect(valid.copyWith(gender: 'unsupported').memberDetailsValid, isFalse);
  });
  test('four-step transitions preserve the immutable raw draft', () {
    final plan = MembershipPlan.fromJson(planJson());
    final review = valid.next().selectPlan(plan).next().next();
    expect(review.step, OnboardingWizardStep.review);
    expect(
      review.previous().previous().previous().step,
      OnboardingWizardStep.memberDetails,
    );
    expect(review.memberCode, valid.memberCode);
    expect(review.firstName, valid.firstName);
    expect(review.selectedPlan, same(plan));
    expect(valid.step, OnboardingWizardStep.memberDetails);
    expect(review.next().step, OnboardingWizardStep.review);
  });
  test('member-only registration skips payment in both directions', () {
    final plan = valid.next().copyWith(registerMemberOnly: true);
    final review = plan.next();
    expect(review.step, OnboardingWizardStep.review);
    expect(review.previous().step, OnboardingWizardStep.membershipPlan);
    final restored = review.previous().copyWith(registerMemberOnly: false);
    expect(restored.next().step, OnboardingWizardStep.membershipPlan);
    expect(restored.canContinue, isFalse);
  });
  test('a plan is required unless member-only registration is chosen', () {
    final draft = valid.next();
    expect(draft.canContinue, isFalse);
    expect(draft.next().step, OnboardingWizardStep.membershipPlan);
    final free = MembershipPlan.fromJson(planJson()..['price'] = 0);
    final selected = draft.selectPlan(free);
    expect(selected.canContinue, isTrue);
    expect(selected.next().step, OnboardingWizardStep.payment);
    expect(draft.selectedPlan, isNull);
  });
  test(
    'member-only registration clears the plan and never restores it silently',
    () {
      final plan = MembershipPlan.fromJson(planJson());
      final selected = valid.next().selectPlan(plan).copyWith(planPage: 2);
      final skipped = selected.copyWith(registerMemberOnly: true);
      expect(skipped.selectedPlan, isNull);
      expect(skipped.canContinue, isTrue);
      expect(skipped.copyWith(firstName: 'Changed').selectedPlan, isNull);
      expect(skipped.copyWith(registerMemberOnly: false).selectedPlan, isNull);
      expect(selected.previous().next().selectedPlan, same(plan));
      expect(selected.previous().next().planPage, 2);
    },
  );
  test('uses MemberDraft normalization without unsupported request fields', () {
    final json = valid.toMemberDraft().toJson(editing: false);
    expect(json, {
      'memberCode': 'ME_01',
      'firstName': 'Alex',
      'lastName': 'River',
      'phone': '9876543210',
    });
    expect(valid.copyWith(gender: 'female').toMemberDraft().gender, 'female');
    expect(valid.copyWith(gender: '').toMemberDraft().gender, isNull);
  });

  group('existing member', () {
    final plan = MembershipPlan.fromJson(planJson());
    OnboardingWizardState existing({String joinedOn = '2026-01-10'}) => valid
        .next()
        .selectPlan(plan)
        .copyWith(existingMember: true, joinedOn: joinedOn);

    test('needs a plan start date of today or earlier to continue', () {
      expect(existing(joinedOn: '').canContinue, isFalse);
      expect(existing(joinedOn: '2999-01-01').canContinue, isFalse);
      expect(existing().canContinue, isTrue);
      expect(existing().next().step, OnboardingWizardStep.payment);
    });

    test('sends the real start date and an opening payment without a '
        'UPI reference', () {
      final review = existing()
          .next()
          .copyWith(
            skipInitialPayment: false,
            paymentAmount: '1000',
            paymentMethod: PaymentMethod.upi,
          )
          .next();
      expect(review.step, OnboardingWizardStep.review);
      final body = review
          .toRequest(gymId: gymA, paidAt: DateTime.now())
          .toJson();
      final membership = body['membership'] as Map<String, dynamic>;
      expect(membership['startDate'], '2026-01-10');
      final payment = membership['payment'] as Map<String, dynamic>;
      expect(payment['openingBalance'], isTrue);
      expect(payment['amountPaise'], 100000);
      expect(payment.containsKey('reference'), isFalse);
      // Dated on the day the plan started, not today.
      expect(
        DateTime.parse(payment['paidAt'] as String).toLocal(),
        DateTime(2026, 1, 10, 12),
      );
    });

    test('a new member still starts today and needs a UPI reference', () {
      final draft = valid
          .next()
          .selectPlan(plan)
          .next()
          .copyWith(
            skipInitialPayment: false,
            paymentAmount: '1000',
            paymentMethod: PaymentMethod.upi,
          );
      expect(draft.initialPaymentReferenceError, isNotNull);
      expect(draft.paymentValid, isFalse);
    });

    test('member-only registration turns the existing-member option off', () {
      expect(
        existing().copyWith(registerMemberOnly: true).existingMember,
        isFalse,
      );
    });
  });
}
