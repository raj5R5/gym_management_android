import '../../memberships/models/billing_models.dart';
import '../data/onboarding_failure.dart';
import 'onboarding_wizard_state.dart';
import 'pending_onboarding.dart';

/// UI support is narrower than store eligibility. The store remains authoritative
/// and rechecks identity, scope, revision and the complete ledger on replacement.
class OnboardingCorrection {
  OnboardingCorrection._(this.operation);
  final PendingOnboardingOperation operation;

  static OnboardingCorrection? supported(PendingOnboardingOperation operation) {
    if (operation.version != 2 ||
        operation.result != null ||
        operation.status != PendingOnboardingStatus.rejected ||
        operation.attempts.isEmpty ||
        !operation.attempts.every(
          (attempt) =>
              attempt.outcome == OnboardingAttemptOutcome.rejected &&
              attempt.rejection?.establishesAttemptNonCommit == true,
        )) {
      return null;
    }
    final code = operation.attempts.last.rejection!.code;
    if (!{
      OnboardingBackendCode.duplicateMemberCode,
      OnboardingBackendCode.duplicatePaymentReference,
      OnboardingBackendCode.validationError,
      OnboardingBackendCode.planNotFound,
      OnboardingBackendCode.paymentOverpayment,
    }.contains(code)) {
      return null;
    }
    final body = operation.request.toJson();
    final member = body['member'] as Map<String, dynamic>;
    final membership = body['membership'] as Map<String, dynamic>?;
    // Do not silently drop fields that this wizard cannot present or edit.
    if (member.keys.any(
          (key) => !{
            'memberCode',
            'firstName',
            'lastName',
            'phone',
            'dateOfBirth',
            'gender',
          }.contains(key),
        ) ||
        !_editableStart(membership?['startDate'])) {
      return null;
    }
    return OnboardingCorrection._(operation);
  }

  /// An existing member's start date (today or earlier) can be corrected in
  /// the wizard; any other saved start date is kept locked.
  static bool _editableStart(Object? startDate) {
    if (startDate == null) return true;
    if (startDate is! String) return false;
    return OnboardingWizardState(
          existingMember: true,
          joinedOn: startDate,
        ).joinedOnDate !=
        null;
  }

  OnboardingBackendCode get code => operation.attempts.last.rejection!.code;

  String get explanation => switch (code) {
    OnboardingBackendCode.duplicateMemberCode =>
      'This member code is already used in this gym. Enter a different member code.',
    OnboardingBackendCode.duplicatePaymentReference =>
      'This payment reference is already recorded. Check the payment and enter its correct, unused reference, or skip the initial payment.',
    OnboardingBackendCode.planNotFound =>
      'The selected plan is unavailable. Choose an available active plan or register the member only.',
    OnboardingBackendCode.paymentOverpayment =>
      'The initial payment exceeded the plan price. Review the current price and amount received.',
    _ =>
      'The backend rejected the details. Review the member, plan and payment information.',
  };

  OnboardingWizardState draft(MembershipPlan? plan) {
    final body = operation.request.toJson();
    final member = body['member'] as Map<String, dynamic>;
    final membership = body['membership'] as Map<String, dynamic>?;
    final payment = membership?['payment'] as Map<String, dynamic>?;
    final amount = payment?['amountPaise'] as int? ?? 0;
    final paid = amount > 0 && plan?.pricePaise != 0;
    return OnboardingWizardState(
      step: membership != null && plan == null
          ? OnboardingWizardStep.membershipPlan
          : switch (code) {
              OnboardingBackendCode.planNotFound =>
                OnboardingWizardStep.membershipPlan,
              OnboardingBackendCode.duplicatePaymentReference ||
              OnboardingBackendCode.paymentOverpayment =>
                OnboardingWizardStep.payment,
              _ => OnboardingWizardStep.memberDetails,
            },
      memberCode: member['memberCode'] as String,
      firstName: member['firstName'] as String,
      lastName: member['lastName'] as String,
      phone: member['phone'] as String,
      dateOfBirth: member['dateOfBirth'] as String? ?? '',
      gender: member['gender'] as String? ?? '',
      registerMemberOnly: membership == null,
      selectedPlan: plan,
      skipInitialPayment: !paid,
      paymentAmount: paid
          ? '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}'
          : '',
      paymentMethod: paid
          ? PaymentMethod.values.firstWhere(
              (method) => method.wireValue == payment!['method'],
            )
          : null,
      paymentReference: paid ? (payment?['reference'] as String? ?? '') : '',
      existingMember: membership?['startDate'] != null,
      joinedOn: membership?['startDate'] as String? ?? '',
    );
  }

  OnboardingReviewIssue? issue(OnboardingWizardState draft) {
    if (operation.attempts.any(
          (attempt) =>
              attempt.rejection?.code ==
              OnboardingBackendCode.duplicateMemberCode,
        ) &&
        draft.memberCode.trim().toUpperCase() ==
            (operation.request.toJson()['member']['memberCode'] as String)
                .trim()
                .toUpperCase()) {
      return const OnboardingReviewIssue(
        OnboardingWizardStep.memberDetails,
        'Enter a different member code before retrying this registration.',
      );
    }
    final originalPayment = operation.request
        .toJson()['membership']?['payment'];
    if (operation.attempts.any(
          (attempt) =>
              attempt.rejection?.code ==
              OnboardingBackendCode.duplicatePaymentReference,
        ) &&
        (draft.initialPaymentPaise ?? 0) > 0 &&
        draft.paymentReference.trim() == originalPayment?['reference']) {
      return const OnboardingReviewIssue(
        OnboardingWizardStep.payment,
        'Check and change the already-used payment reference, or skip initial payment.',
      );
    }
    return null;
  }
}
