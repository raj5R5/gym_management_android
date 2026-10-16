import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../memberships/billing_fakes.dart';

void main() {
  const member = OnboardingWizardState(
    step: OnboardingWizardStep.review,
    memberCode: ' me01 ',
    firstName: ' Alex ',
    lastName: ' River ',
    phone: ' 9876543210 ',
    dateOfBirth: '2000-01-02',
    gender: 'female',
  );
  final membership = member.selectPlan(MembershipPlan.fromJson(planJson()));
  final paidAt = DateTime.utc(2026, 1, 1, 10, 0, 0, 123, 456);

  test(
    'member-only maps collected fields and omits all membership/payment fields',
    () {
      final draft = member.copyWith(registerMemberOnly: true);
      expect(draft.canConfirm(gymId: gymA), isTrue);
      expect(draft.toRequest(gymId: gymA, paidAt: paidAt).toJson(), {
        'member': {
          'memberCode': 'ME01',
          'firstName': 'Alex',
          'lastName': 'River',
          'phone': '9876543210',
          'dateOfBirth': '2000-01-02',
          'gender': 'female',
        },
      });
    },
  );
  test(
    'membership omits unsupported fields, start date and skipped payment',
    () {
      final request = membership.toRequest(gymId: gymA, paidAt: paidAt);
      expect(request.toJson()['membership'], {'planId': planId});
      final detached = request.toJson();
      (detached['member'] as Map)['firstName'] = 'Changed';
      expect((request.toJson()['member'] as Map)['firstName'], 'Alex');
    },
  );
  for (final method in PaymentMethod.values) {
    test(
      'positive ${method.wireValue} maps paise, method, fixed millisecond timestamp and reference',
      () {
        final draft = membership.copyWith(
          skipInitialPayment: false,
          paymentAmount: '500.03',
          paymentMethod: method,
          paymentReference: method.requiresReference ? ' REF-123 ' : '',
        );
        final request = draft.toRequest(gymId: gymA, paidAt: paidAt);
        final payment =
            (request.toJson()['membership'] as Map)['payment'] as Map;
        expect(payment, {
          'method': method.wireValue,
          'amountPaise': 50003,
          'paidAt': '2026-01-01T10:00:00.123Z',
          if (method.requiresReference) 'reference': 'REF-123',
        });
        expect(draft.remainingBalancePaise, 99997);
      },
    );
  }
  test('zero initial payment omits payment object entirely', () {
    final draft = membership.copyWith(
      skipInitialPayment: false,
      paymentAmount: '0',
      paymentMethod: PaymentMethod.upi,
    );
    expect(
      draft.toRequest(gymId: gymA, paidAt: paidAt).toJson()['membership'],
      {'planId': planId},
    );
  });
  test('free plan omits payment and has zero remaining balance', () {
    final draft = member.selectPlan(
      MembershipPlan.fromJson({...planJson(), 'price': 0}),
    );
    expect(
      draft.toRequest(gymId: gymA, paidAt: paidAt).toJson()['membership'],
      {'planId': planId},
    );
    expect(draft.remainingBalancePaise, 0);
  });
  for (final draft in [
    member,
    member.copyWith(registerMemberOnly: true, phone: '123'),
    member.copyWith(registerMemberOnly: true, firstName: ''),
    member.copyWith(registerMemberOnly: true, dateOfBirth: '2000-02-30'),
    membership.copyWith(step: OnboardingWizardStep.payment),
    membership.copyWith(skipInitialPayment: false, paymentAmount: '-1'),
    membership.copyWith(skipInitialPayment: false, paymentAmount: '1500.01'),
    membership.copyWith(
      skipInitialPayment: false,
      paymentAmount: '1',
      paymentMethod: PaymentMethod.upi,
    ),
    member.selectPlan(
      MembershipPlan.fromJson({...planJson(), 'status': 'inactive'}),
    ),
    member.selectPlan(MembershipPlan.fromJson({...planJson(), 'gymId': gymB})),
  ].indexed) {
    test('invalid or non-review draft ${draft.$1} cannot freeze a request', () {
      expect(draft.$2.canConfirm(gymId: gymA), isFalse);
      expect(
        () => draft.$2.toRequest(gymId: gymA, paidAt: paidAt),
        throwsFormatException,
      );
    });
  }
}
