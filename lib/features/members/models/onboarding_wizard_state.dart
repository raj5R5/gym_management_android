import '../../admin_dashboard/models/dashboard_models.dart';
import '../../memberships/models/billing_models.dart';
import 'member_draft.dart';
import 'member_models.dart';
import 'onboarding_models.dart';

enum OnboardingWizardStep {
  memberDetails('Member Details'),
  membershipPlan('Membership Plan'),
  payment('Payment'),
  review('Review & Confirm');

  const OnboardingWizardStep(this.title);
  final String title;
}

class OnboardingReviewIssue {
  const OnboardingReviewIssue(this.step, this.message);
  final OnboardingWizardStep step;
  final String message;
}

/// Local presentation draft. A validated conversion freezes the request only
/// when the recovery gate accepts an explicit confirmation.
class OnboardingWizardState {
  const OnboardingWizardState({
    this.step = OnboardingWizardStep.memberDetails,
    this.memberCode = '',
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.dateOfBirth = '',
    this.gender = '',
    this.registerMemberOnly = false,
    this.selectedPlan,
    this.planPage = 1,
    this.skipInitialPayment = true,
    this.paymentAmount = '',
    this.paymentMethod,
    this.paymentReference = '',
    this.existingMember = false,
    this.joinedOn = '',
  }) : assert(!registerMemberOnly || selectedPlan == null),
       assert(planPage > 0);

  final OnboardingWizardStep step;
  final String memberCode, firstName, lastName, phone, dateOfBirth, gender;
  final bool registerMemberOnly;
  final MembershipPlan? selectedPlan;
  final int planPage;
  final bool skipInitialPayment;
  // Raw field text is retained for editing; all calculated money is integer paise.
  final String paymentAmount, paymentReference;
  final PaymentMethod? paymentMethod;

  /// Already a member before the gym used the app: their plan started on
  /// [joinedOn] (YYYY-MM-DD) and the payment is what they had paid then.
  final bool existingMember;
  final String joinedOn;

  /// [joinedOn] when it is a valid day up to today; otherwise null.
  CalendarDate? get joinedOnDate {
    try {
      final day = CalendarDate.parse(joinedOn.trim());
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      return day.value.isAfter(today) ? null : day;
    } on FormatException {
      return null;
    }
  }

  /// User-entered content only: moving steps or paging plans is not an edit.
  Object get draftValues => (
    memberCode,
    firstName,
    lastName,
    phone,
    dateOfBirth,
    gender,
    registerMemberOnly,
    selectedPlan?.id,
    skipInitialPayment,
    paymentAmount,
    paymentMethod,
    paymentReference,
    existingMember,
    joinedOn,
  );

  /// Local consistency checks only; final authorization/pricing remain server-owned.
  List<OnboardingReviewIssue> reviewIssues({required String gymId}) {
    final issues = <OnboardingReviewIssue>[];
    void memberIssue(String label, String? error) {
      if (error != null) {
        issues.add(
          OnboardingReviewIssue(
            OnboardingWizardStep.memberDetails,
            '$label: $error',
          ),
        );
      }
    }

    memberIssue('Member code', validateMemberCode(memberCode));
    memberIssue('First name', validateName(firstName));
    memberIssue('Last name', validateName(lastName));
    memberIssue('Phone', validatePhone(phone));
    memberIssue('Date of birth', validateMemberBirthDate(dateOfBirth));
    memberIssue(
      'Gender',
      gender.isEmpty || memberGenders.contains(gender)
          ? null
          : 'Select a supported option or leave gender unspecified.',
    );

    if (registerMemberOnly) {
      if (selectedPlan != null ||
          !skipInitialPayment ||
          paymentAmount.isNotEmpty ||
          paymentMethod != null ||
          paymentReference.isNotEmpty) {
        issues.add(
          const OnboardingReviewIssue(
            OnboardingWizardStep.membershipPlan,
            'Member-only registration must not include a plan or initial payment.',
          ),
        );
      }
      return List.unmodifiable(issues);
    }
    final plan = selectedPlan;
    if (plan == null) {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.membershipPlan,
          'Choose a membership plan or register the member only.',
        ),
      );
      return List.unmodifiable(issues);
    }
    if (existingMember && joinedOnDate == null) {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.membershipPlan,
          'Choose the date their current plan started (today or earlier).',
        ),
      );
    }
    if (plan.gymId != gymId || plan.status != 'active') {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.membershipPlan,
          'Choose an active membership plan for the current gym.',
        ),
      );
    }
    try {
      onboardingId(plan.id);
    } on FormatException {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.membershipPlan,
          'The selected plan could not be verified. Choose a plan again.',
        ),
      );
    }
    if (skipInitialPayment &&
        (paymentAmount.isNotEmpty ||
            paymentMethod != null ||
            paymentReference.isNotEmpty)) {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.payment,
          'Clear the payment details when skipping initial payment.',
        ),
      );
    }
    if (paymentAmountError case final error?) {
      issues.add(OnboardingReviewIssue(OnboardingWizardStep.payment, error));
    }
    if ((initialPaymentPaise ?? 0) > 0 && paymentMethod == null) {
      issues.add(
        const OnboardingReviewIssue(
          OnboardingWizardStep.payment,
          'Select a payment method.',
        ),
      );
    }
    if (initialPaymentReferenceError case final error?) {
      issues.add(OnboardingReviewIssue(OnboardingWizardStep.payment, error));
    }
    return List.unmodifiable(issues);
  }

  String? get paymentAmountError {
    if (skipInitialPayment) return null;
    if (selectedPlan == null) return 'Select a membership plan first.';
    try {
      final amount = parsePaymentRupees(paymentAmount, allowZero: true);
      return amount > selectedPlan!.pricePaise
          ? 'Initial payment cannot exceed the plan price.'
          : null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  int? get initialPaymentPaise {
    if (registerMemberOnly ||
        skipInitialPayment ||
        selectedPlan?.pricePaise == 0) {
      return 0;
    }
    if (paymentAmountError != null) return null;
    return parsePaymentRupees(paymentAmount, allowZero: true);
  }

  String? get initialPaymentReferenceError {
    if ((initialPaymentPaise ?? 0) == 0 || paymentMethod == null) return null;
    // Money paid before the app: a UPI or card reference is optional.
    if (existingMember && paymentReference.trim().isEmpty) return null;
    return paymentReferenceError(paymentMethod!, paymentReference);
  }

  bool get paymentValid =>
      selectedPlan != null &&
      !registerMemberOnly &&
      paymentAmountError == null &&
      (initialPaymentPaise == 0 || paymentMethod != null) &&
      initialPaymentReferenceError == null;

  int? get remainingBalancePaise => initialPaymentPaise == null
      ? null
      : (selectedPlan?.pricePaise ?? 0) - initialPaymentPaise!;

  /// A local conversion only. The submission milestone owns the paid timestamp.
  OnboardingPayment? toInitialPayment({required DateTime paidAt}) {
    if (registerMemberOnly ||
        selectedPlan == null ||
        skipInitialPayment ||
        selectedPlan!.pricePaise == 0) {
      return null;
    }
    if (!paymentValid) throw const FormatException('Invalid initial payment.');
    final amount = initialPaymentPaise!;
    return amount == 0
        ? null
        : OnboardingPayment(
            method: paymentMethod!,
            amountPaise: amount,
            paidAt: existingMember ? openingPaidAt(paidAt) : paidAt,
            reference: paymentReference,
            openingBalance: existingMember,
          );
  }

  /// An opening payment is dated on the plan's start day (midday), never
  /// later than [now].
  DateTime openingPaidAt(DateTime now) {
    final day = joinedOnDate?.value;
    if (day == null) return now;
    final midday = DateTime(day.year, day.month, day.day, 12);
    return midday.isAfter(now) ? now : midday;
  }

  bool canConfirm({required String gymId}) =>
      step == OnboardingWizardStep.review && reviewIssues(gymId: gymId).isEmpty;

  OnboardingRequest toRequest({
    required String gymId,
    required DateTime paidAt,
  }) {
    if (!canConfirm(gymId: gymId)) {
      throw const FormatException(
        'Check the registration details before confirming.',
      );
    }
    return OnboardingRequest(
      member: toMemberDraft(),
      membership: registerMemberOnly
          ? null
          : OnboardingMembership(
              planId: selectedPlan!.id,
              // New members start today: omitting the date lets the backend
              // resolve gym-local today. Existing members keep their real start.
              startDate: existingMember ? joinedOnDate : null,
              payment: toInitialPayment(paidAt: paidAt),
            ),
    );
  }

  bool get canContinue => switch (step) {
    OnboardingWizardStep.memberDetails => memberDetailsValid,
    OnboardingWizardStep.membershipPlan =>
      registerMemberOnly ||
          selectedPlan != null && (!existingMember || joinedOnDate != null),
    OnboardingWizardStep.payment => paymentValid,
    OnboardingWizardStep.review => false,
  };

  bool get memberDetailsValid =>
      validateMemberCode(memberCode) == null &&
      validateName(firstName) == null &&
      validateName(lastName) == null &&
      validatePhone(phone) == null &&
      validateBirthDate(dateOfBirth) == null &&
      (gender.isEmpty || memberGenders.contains(gender));

  MemberDraft toMemberDraft() => MemberDraft(
    memberCode: memberCode,
    firstName: firstName,
    lastName: lastName,
    phone: phone,
    dateOfBirth: dateOfBirth.trim().isEmpty
        ? null
        : CalendarDate.parse(dateOfBirth.trim()),
    gender: gender.isEmpty ? null : gender,
  );

  OnboardingWizardState copyWith({
    OnboardingWizardStep? step,
    String? memberCode,
    String? firstName,
    String? lastName,
    String? phone,
    String? dateOfBirth,
    String? gender,
    bool? registerMemberOnly,
    MembershipPlan? selectedPlan,
    int? planPage,
    bool clearSelectedPlan = false,
    bool? skipInitialPayment,
    String? paymentAmount,
    PaymentMethod? paymentMethod,
    String? paymentReference,
    bool? existingMember,
    String? joinedOn,
  }) {
    final memberOnly = registerMemberOnly ?? this.registerMemberOnly;
    final plan = memberOnly || clearSelectedPlan
        ? null
        : selectedPlan ?? this.selectedPlan;
    final skip =
        plan == null ||
        plan.pricePaise == 0 ||
        (skipInitialPayment ?? this.skipInitialPayment);
    return OnboardingWizardState(
      step: step ?? this.step,
      memberCode: memberCode ?? this.memberCode,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      registerMemberOnly: memberOnly,
      selectedPlan: plan,
      planPage: planPage ?? this.planPage,
      skipInitialPayment: skip,
      paymentAmount: skip ? '' : paymentAmount ?? this.paymentAmount,
      paymentMethod: skip
          ? null
          : paymentMethod ?? this.paymentMethod ?? PaymentMethod.cash,
      paymentReference: skip ? '' : paymentReference ?? this.paymentReference,
      existingMember: memberOnly
          ? false
          : existingMember ?? this.existingMember,
      joinedOn: joinedOn ?? this.joinedOn,
    );
  }

  OnboardingWizardState selectPlan(MembershipPlan plan) =>
      copyWith(selectedPlan: plan, registerMemberOnly: false);

  OnboardingWizardState next() => copyWith(
    step: switch (step) {
      OnboardingWizardStep.memberDetails =>
        memberDetailsValid
            ? OnboardingWizardStep.membershipPlan
            : OnboardingWizardStep.memberDetails,
      OnboardingWizardStep.membershipPlan =>
        registerMemberOnly
            ? OnboardingWizardStep.review
            : selectedPlan != null && (!existingMember || joinedOnDate != null)
            ? OnboardingWizardStep.payment
            : OnboardingWizardStep.membershipPlan,
      OnboardingWizardStep.payment =>
        paymentValid
            ? OnboardingWizardStep.review
            : OnboardingWizardStep.payment,
      OnboardingWizardStep.review => OnboardingWizardStep.review,
    },
  );

  OnboardingWizardState previous() => copyWith(
    step: switch (step) {
      OnboardingWizardStep.memberDetails => OnboardingWizardStep.memberDetails,
      OnboardingWizardStep.membershipPlan => OnboardingWizardStep.memberDetails,
      OnboardingWizardStep.payment => OnboardingWizardStep.membershipPlan,
      OnboardingWizardStep.review =>
        registerMemberOnly
            ? OnboardingWizardStep.membershipPlan
            : OnboardingWizardStep.payment,
    },
  );
}
