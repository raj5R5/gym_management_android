import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
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
}
