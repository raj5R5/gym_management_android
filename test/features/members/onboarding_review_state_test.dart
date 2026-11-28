import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../memberships/billing_fakes.dart';

void main() {
  const member = OnboardingWizardState(
    memberCode: ' ME01 ',
    firstName: ' Alex ',
    lastName: ' River ',
    phone: '9876543210',
    dateOfBirth: '2000-01-02',
    gender: 'female',
  );
  final membership = member.selectPlan(MembershipPlan.fromJson(planJson()));
  final payment = membership.copyWith(
    skipInitialPayment: false,
    paymentAmount: '500.03',
    paymentMethod: PaymentMethod.upi,
    paymentReference: 'REF-123',
  );

  for (final entry in {
    'member only': member.copyWith(registerMemberOnly: true),
    'membership only': membership,
    'membership and payment': payment,
  }.entries) {
    test('${entry.key} passes local review for explicit confirmation', () {
      final review = entry.value.copyWith(step: OnboardingWizardStep.review);
      expect(review.reviewIssues(gymId: gymA), isEmpty);
      expect(review.canContinue, isFalse);
      expect(review.canConfirm(gymId: gymA), isTrue);
    });
  }
  for (final entry in {
    // A code is optional, but a typed one must still be well formed.
    'member code': member.copyWith(memberCode: 'x'),
    'first name': member.copyWith(firstName: ''),
    'last name': member.copyWith(lastName: ''),
    'phone': member.copyWith(phone: '123'),
    'birth date': member.copyWith(dateOfBirth: '2000-02-30'),
    'gender': member.copyWith(gender: 'unsupported'),
  }.entries) {
    test('invalid ${entry.key} directs correction to Member Details', () {
      final issues = entry.value
          .copyWith(registerMemberOnly: true)
          .reviewIssues(gymId: gymA);
      expect(issues.length, 1);
      expect(issues.single.step, OnboardingWizardStep.memberDetails);
    });
  }
  test('missing plan directs correction to Membership Plan', () {
    final issues = member.reviewIssues(gymId: gymA);
    expect(issues.single.step, OnboardingWizardStep.membershipPlan);
    expect(issues.single.message, contains('Choose a membership plan'));
  });
  for (final invalid in [
    planJson()..['status'] = 'inactive',
    planJson()..['gymId'] = gymB,
    planJson()..['id'] = 'invalid-id',
  ]) {
    test(
      'invalid plan ${invalid['id']}/${invalid['status']}/${invalid['gymId']} cannot pass review',
      () {
        final draft = member.selectPlan(MembershipPlan.fromJson(invalid));
        expect(
          draft.reviewIssues(gymId: gymA).single.step,
          OnboardingWizardStep.membershipPlan,
        );
      },
    );
  }
  for (final entry in {
    'invalid amount': payment.copyWith(paymentAmount: '-1'),
    'overpayment': payment.copyWith(paymentAmount: '1500.01'),
    'missing reference': payment.copyWith(paymentReference: ''),
  }.entries) {
    test('${entry.key} directs correction to Payment', () {
      final issues = entry.value.reviewIssues(gymId: gymA);
      expect(issues.single.step, OnboardingWizardStep.payment);
    });
  }
  test('missing positive-payment method is explained', () {
    final draft = OnboardingWizardState(
      memberCode: 'ME01',
      firstName: 'Alex',
      lastName: 'River',
      phone: '9876543210',
      selectedPlan: membership.selectedPlan,
      skipInitialPayment: false,
      paymentAmount: '100',
    );
    final issue = draft.reviewIssues(gymId: gymA).single;
    expect(issue.step, OnboardingWizardStep.payment);
    expect(issue.message, 'Select a payment method.');
  });
  test('free and zero-payment plans are valid and show integer balances', () {
    final free = member.selectPlan(
      MembershipPlan.fromJson(planJson()..['price'] = 0),
    );
    expect(free.reviewIssues(gymId: gymA), isEmpty);
    expect(free.remainingBalancePaise, 0);
    final zero = payment.copyWith(paymentAmount: '0', paymentReference: '');
    expect(zero.reviewIssues(gymId: gymA), isEmpty);
    expect(zero.remainingBalancePaise, 150000);
    expect(payment.remainingBalancePaise, 99997);
  });
  test(
    'review rejects leftover details when payment was marked as skipped',
    () {
      final draft = OnboardingWizardState(
        memberCode: 'ME01',
        firstName: 'Alex',
        lastName: 'River',
        phone: '9876543210',
        selectedPlan: membership.selectedPlan,
        paymentAmount: '100',
        paymentMethod: PaymentMethod.cash,
      );
      expect(
        draft.reviewIssues(gymId: gymA).single.step,
        OnboardingWizardStep.payment,
      );
    },
  );
  test('member-only review rejects inconsistent leftover payment details', () {
    const draft = OnboardingWizardState(
      memberCode: 'ME01',
      firstName: 'Alex',
      lastName: 'River',
      phone: '9876543210',
      registerMemberOnly: true,
      paymentReference: 'REF-123',
    );
    expect(
      draft.reviewIssues(gymId: gymA).single.step,
      OnboardingWizardStep.membershipPlan,
    );
  });
  test(
    'editing earlier steps preserves the raw draft and review issues are immutable',
    () {
      final review = payment.copyWith(step: OnboardingWizardStep.review);
      final edited = review.copyWith(step: OnboardingWizardStep.memberDetails);
      expect(edited.firstName, ' Alex ');
      expect(edited.dateOfBirth, '2000-01-02');
      expect(edited.selectedPlan, same(review.selectedPlan));
      expect(edited.paymentAmount, '500.03');
      expect(edited.paymentMethod, PaymentMethod.upi);
      expect(edited.paymentReference, 'REF-123');
      expect(
        () => edited.reviewIssues(gymId: gymA).clear(),
        throwsUnsupportedError,
      );
    },
  );
}
