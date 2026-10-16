import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/members/models/onboarding_wizard_state.dart';
import 'package:gym_management_app/features/members/presentation/onboarding_review_step.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/shared/widgets/soft_panel.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../memberships/billing_fakes.dart';

void main() {
  const member = OnboardingWizardState(
    step: OnboardingWizardStep.review,
    memberCode: ' me_01 ',
    firstName: ' Alex ',
    lastName: ' River ',
    phone: ' 9876543210 ',
    dateOfBirth: '2000-01-02',
    gender: 'non_binary',
  );
  final membership = member.selectPlan(MembershipPlan.fromJson(planJson()));
  final payment = membership.copyWith(
    skipInitialPayment: false,
    paymentAmount: '500.03',
    paymentMethod: PaymentMethod.upi,
    paymentReference: ' REF-123 ',
  );

  Future<List<OnboardingWizardStep>> pump(
    WidgetTester tester,
    OnboardingWizardState draft, {
    Brightness brightness = Brightness.light,
  }) async {
    final edits = <OnboardingWizardStep>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SoftPanel(
              child: OnboardingReviewStep(
                draft: draft,
                gymId: gymA,
                onEdit: edits.add,
              ),
            ),
          ),
        ),
      ),
    );
    return edits;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await Scrollable.ensureVisible(
      tester.element(find.text(text)),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'member-only review accurately normalizes collected optional fields',
    (tester) async {
      await pump(tester, member.copyWith(registerMemberOnly: true));
      expect(find.text('Member registration only'), findsOneWidget);
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.text('Member code: ME_01'), findsOneWidget);
      expect(find.text('Phone: 9876543210'), findsOneWidget);
      expect(find.text('Date of birth: 2000-01-02'), findsOneWidget);
      expect(find.text('Gender: non binary'), findsOneWidget);
      expect(find.textContaining('Membership plan:'), findsNothing);
      expect(find.textContaining('Remaining balance:'), findsNothing);
      expect(find.text(onboardingConfirmationMessage), findsOneWidget);
    },
  );
  testWidgets(
    'uncollected optional fields are omitted rather than fabricated',
    (tester) async {
      await pump(
        tester,
        member.copyWith(dateOfBirth: '', gender: '', registerMemberOnly: true),
      );
      expect(find.textContaining('Date of birth:'), findsNothing);
      expect(find.textContaining('Gender:'), findsNothing);
      expect(find.textContaining('Address:'), findsNothing);
    },
  );
  testWidgets(
    'membership without payment shows the plan and full outstanding balance',
    (tester) async {
      await pump(tester, membership);
      expect(find.text('Member + membership'), findsOneWidget);
      expect(find.text('No initial payment will be recorded.'), findsOneWidget);
      expect(find.text('Membership plan: Monthly'), findsOneWidget);
      expect(find.text('30 days · ₹1,500.00'), findsOneWidget);
      expect(find.text('Plan price: ₹1,500.00'), findsOneWidget);
      expect(find.text('Initial payment: ₹0.00'), findsOneWidget);
      expect(find.text('Remaining balance: ₹1,500.00'), findsOneWidget);
      expect(
        find.textContaining('Start date: Set by the backend'),
        findsOneWidget,
      );
      expect(find.textContaining('Payment method:'), findsNothing);
    },
  );
  testWidgets(
    'membership with initial payment shows exact price, method, reference and balance',
    (tester) async {
      await pump(tester, payment);
      expect(
        find.text('Member + membership + initial payment'),
        findsOneWidget,
      );
      expect(find.text('Plan price: ₹1,500.00'), findsOneWidget);
      expect(find.text('Initial payment: ₹500.03'), findsOneWidget);
      expect(find.text('Payment method: UPI'), findsOneWidget);
      expect(find.text('Reference: REF-123'), findsOneWidget);
      expect(find.text('Remaining balance: ₹999.97'), findsOneWidget);
    },
  );
  testWidgets(
    'free plan shows zero balance and explicitly says no payment is due',
    (tester) async {
      await pump(
        tester,
        member.selectPlan(MembershipPlan.fromJson(planJson()..['price'] = 0)),
      );
      expect(
        find.text('Free plan · ₹0.00. No payment is due.'),
        findsOneWidget,
      );
      expect(find.text('Plan price: ₹0.00'), findsOneWidget);
      expect(find.text('Remaining balance: ₹0.00'), findsOneWidget);
      expect(find.textContaining('Payment method:'), findsNothing);
    },
  );
  testWidgets(
    'zero configured payment is presented as membership without a payment',
    (tester) async {
      await pump(
        tester,
        payment.copyWith(paymentAmount: '0.00', paymentReference: ''),
      );
      expect(find.text('Member + membership'), findsOneWidget);
      expect(find.text('Initial payment: ₹0.00'), findsOneWidget);
      expect(find.textContaining('Payment method:'), findsNothing);
      expect(find.textContaining('Reference:'), findsNothing);
    },
  );
  for (final entry in {
    'missing name': member.copyWith(firstName: ''),
    'invalid phone': member.copyWith(phone: '123'),
    'invalid optional date': member.copyWith(dateOfBirth: '2000-02-30'),
  }.entries) {
    testWidgets(
      '${entry.key} explains the issue without throwing during normalization',
      (tester) async {
        final edits = await pump(
          tester,
          entry.value.copyWith(registerMemberOnly: true),
        );
        expect(
          find.text('Fix these details before registration'),
          findsOneWidget,
        );
        await tap(tester, 'Fix Member Details');
        expect(edits, [OnboardingWizardStep.memberDetails]);
        expect(find.text(onboardingConfirmationMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'missing plan explains the problem and links to Membership Plan',
    (tester) async {
      final edits = await pump(tester, member);
      expect(
        find.text('Choose a membership plan or register the member only.'),
        findsOneWidget,
      );
      expect(find.text('No membership plan selected.'), findsOneWidget);
      await tap(tester, 'Fix Membership Plan');
      expect(edits, [OnboardingWizardStep.membershipPlan]);
    },
  );
  for (final entry in {
    'overpayment': payment.copyWith(paymentAmount: '1500.01'),
    'missing reference': payment.copyWith(paymentReference: ''),
  }.entries) {
    testWidgets('${entry.key} explains the correction and links to Payment', (
      tester,
    ) async {
      final edits = await pump(tester, entry.value);
      expect(
        find.text('Fix these details before registration'),
        findsOneWidget,
      );
      await tap(tester, 'Fix Payment');
      expect(edits, [OnboardingWizardStep.payment]);
      if (entry.key == 'overpayment') {
        expect(
          find.text('Remaining balance: Enter a valid amount'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('each review edit action targets the correct earlier step', (
    tester,
  ) async {
    final edits = await pump(tester, payment);
    await tap(tester, 'Edit member details');
    await tap(tester, 'Edit membership selection');
    await tap(tester, 'Edit initial payment');
    expect(edits, [
      OnboardingWizardStep.memberDetails,
      OnboardingWizardStep.membershipPlan,
      OnboardingWizardStep.payment,
    ]);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'review sections fit 320px with double text scaling in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester, payment, brightness: brightness);
        await tap(tester, 'Edit initial payment');
        await Scrollable.ensureVisible(
          tester.element(find.text(onboardingConfirmationMessage)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remaining balance: ₹999.97'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
