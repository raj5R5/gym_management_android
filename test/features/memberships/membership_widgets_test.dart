import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'package:gym_management_app/features/adjustments/adjustments.dart';
import '../money/adjustment_fakes.dart';
import '../members/photo_fakes.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../members/onboarding_fakes.dart'
    show TestOnboardingStorage, onboardingUrl;
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'dart:async';
import 'package:gym_management_app/features/memberships/models/renewal_preview.dart';
import 'package:gym_management_app/features/memberships/models/renewal_payment_draft.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/presentation/cancellation_confirmation_sheet.dart';
import 'package:gym_management_app/features/memberships/presentation/renewal_confirmation_sheet.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_management_app/features/memberships/presentation/plans_page.dart'
    show PlanFormPage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/memberships/presentation/payment_transaction_details.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/presentation/billing_components.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import '../trainers/trainer_fakes.dart' show FakeTrainerRepository;
import 'package:gym_management_app/features/trainers/providers/trainer_providers.dart'
    show trainerRepositoryProvider;
import 'billing_fakes.dart';
import 'renewal_fakes.dart';
import 'package:gym_management_app/features/memberships/data/pending_renewal_store.dart';
import 'package:gym_management_app/features/memberships/providers/renewal_providers.dart';
import 'package:gym_management_app/features/memberships/providers/plan_providers.dart';

void main() {
  late FakeMembershipRepository billing;
  late ActiveMembershipMemberRepository members;
  late FakeAuthApi api;
  late ProviderContainer container;
  Future<void> pump(
    WidgetTester tester, {
    bool authenticated = true,
    AuthRole role = AuthRole.admin,
    String? path,
  }) async {
    billing = FakeMembershipRepository();
    members = ActiveMembershipMemberRepository()
      ..populated = true
      ..historyRecords = expiredHistoryFixture();
    api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    container = ProviderContainer(
      overrides: [
        renewalRepositoryProvider.overrideWithValue(
          FakeRenewalRepository(billing),
        ),
        pendingRenewalStoreProvider.overrideWithValue(
          PendingRenewalStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        ),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(members),
        trainerRepositoryProvider.overrideWithValue(FakeTrainerRepository()),
        membershipRepositoryProvider.overrideWithValue(billing),
        adjustmentRepositoryProvider.overrideWithValue(
          FakeAdjustmentRepository(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GymApp(animateDecorations: false),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(appRouterProvider)
        .go(path ?? '${AppRoutes.members}/$memberId/membership?gymId=$gymA');
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> purchase(WidgetTester tester) =>
      tap(tester, find.text('Purchase membership'));
  Future<void> selectPlan(WidgetTester tester) =>
      tap(tester, find.widgetWithText(ListTile, 'Monthly'));
  Future<void> review(WidgetTester tester) =>
      tap(tester, find.widgetWithText(FilledButton, 'Review purchase'));
  Future<void> detail(WidgetTester tester) async {
    final scope = scopeFor(container.read(adminGymProvider)!, memberId);
    container
        .read(appRouterProvider)
        .go(membershipPath(scope, subscriptionId: subscriptionId));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Member Details opens membership with server current, history and payments',
    (tester) async {
      await pump(tester, path: '${AppRoutes.members}/$memberId?gymId=$gymA');
      members.historyRecords = null;
      container.invalidate(memberHistoryProvider);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Payments'));
      expect(find.text('Membership & payments'), findsOneWidget);
      expect(find.text('Current membership'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
      expect(find.text('₹1,496.97'), findsOneWidget);
      await reveal(tester, find.text('Successful payment history'));
      // One row per payment: amount, then method and time.
      expect(
        find.descendant(
          of: find.byType(PaymentRow),
          matching: find.text('₹3.03'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Cash ·'), findsOneWidget);
      expect(find.byTooltip('Share receipt'), findsOneWidget);
      expect(
        billing.operations.where((e) => e.startsWith('payments')).length,
        1,
      );
    },
  );

  testWidgets(
    'active membership blocks purchase and shows its saved plan and expiry',
    (tester) async {
      await pump(tester);
      members.historyRecords = [
        subscriptionJson()..addAll({
          'endDate': '2026-12-12',
          'paymentSummary': {
            'totalSuccessfulPaidPaise': 150000,
            'remainingBalancePaise': 0,
          },
        }),
      ];
      await purchase(tester);
      expect(
        find.textContaining('already has an unexpired membership'),
        findsOneWidget,
      );
      expect(find.text('12 Dec 2026'), findsOneWidget);
      expect(find.text('Review purchase'), findsNothing);
      expect(billing.purchases, isEmpty);
      await tap(tester, find.text('View existing membership & payments'));
      expect(find.byType(RenewalConfirmationSheet), findsNothing);
      expect(find.text('Membership details'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    },
  );
  testWidgets(
    'active membership blocks entering renewal but keeps normal payments available',
    (tester) async {
      await pump(tester);
      members.historyRecords = [subscriptionJson()..['endDate'] = '2026-12-12'];
      await detail(tester);
      expect(find.text('Record Payment'), findsOneWidget);
      await tap(tester, find.text('Review renewal'));
      expect(
        find.textContaining('already has an unexpired membership'),
        findsOneWidget,
      );
      expect(find.text('12 Dec 2026'), findsOneWidget);
      expect(find.text('Confirm Renewal'), findsNothing);
      expect(billing.renewals, isEmpty);
      await tap(tester, find.text('View existing membership & payments'));
      expect(find.byType(RenewalConfirmationSheet), findsNothing);
      expect(find.text('Membership details'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    },
  );
  testWidgets(
    'purchase confirmation rechecks server history rather than trusting its entry snapshot',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await review(tester);
      members.historyRecords = [subscriptionJson()];
      await tap(tester, find.text('Confirm purchase'));
      expect(billing.purchases, isEmpty);
      expect(
        find.textContaining('already has an unexpired membership'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'renewal confirmation rechecks eligibility before creating a recovery operation',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.text('Review renewal'));
      await tap(tester, find.text('Continue to Payment'));
      await tap(tester, find.text('Review & Confirm'));
      members.historyRecords = [subscriptionJson()];
      await tap(tester, find.text('Confirm Renewal'));
      expect(billing.renewals, isEmpty);
      expect(
        find.textContaining('already has an unexpired membership'),
        findsOneWidget,
      );
      final request = (
        scope: scopeFor(container.read(adminGymProvider)!, memberId),
        subscriptionId: subscriptionId,
      );
      expect(
        container.read(renewalControllerProvider(request).notifier).saved,
        isNull,
      );
    },
  );
  testWidgets('purchase requires plan selection and review before POST', (
    tester,
  ) async {
    await pump(tester);
    await purchase(tester);
    await review(tester);
    expect(find.text('Select an active membership plan.'), findsOneWidget);
    expect(billing.purchases, isEmpty);
    await selectPlan(tester);
    await review(tester);
    expect(find.text('No payment will be recorded.'), findsOneWidget);
    expect(billing.purchases, isEmpty);
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
    expect(billing.purchases.length, 1);
    expect(billing.purchases.single.payment, isNull);
    expect(find.text('Server confirmation'), findsOneWidget);
    expect(find.textContaining('Mar 1, 2026 → Mar 31, 2026'), findsOneWidget);
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'View updated history'),
    );
    expect(find.text('Membership & payments'), findsOneWidget);
  });
  testWidgets(
    'payment input validates money and digital reference before review',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await reveal(tester, find.byKey(const ValueKey('paymentAmount')));
      await tester.enterText(
        find.byKey(const ValueKey('paymentAmount')),
        '1.001',
      );
      await review(tester);
      expect(
        find.text('Enter rupees with at most two decimal places.'),
        findsOneWidget,
      );
      expect(billing.purchases, isEmpty);
      await reveal(tester, find.byKey(const ValueKey('paymentAmount')));
      await tester.enterText(
        find.byKey(const ValueKey('paymentAmount')),
        '3.03',
      );
      await tap(tester, find.byKey(const ValueKey('paymentMethod')));
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await review(tester);
      expect(find.text('A payment reference is required.'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('paymentReference')));
      await tester.enterText(
        find.byKey(const ValueKey('paymentReference')),
        ' REF-001 ',
      );
      await review(tester);
      expect(find.text('Payment to record: ₹3.03 · UPI'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment!.amountPaise, 303);
      expect(billing.purchases.single.payment!.reference, 'REF-001');
    },
  );
  testWidgets(
    'cancel requires explicit confirmation and preserves server history',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel membership'));
      expect(billing.operations.where((e) => e.startsWith('cancel')), isEmpty);
      expect(find.textContaining('No refund is created'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('cancellationReason')));
      await tester.enterText(
        find.byKey(const ValueKey('cancellationReason')),
        'Requested',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Confirm Cancellation'),
      );
      expect(billing.operations, contains('cancel:Requested'));
      expect(find.text('Server confirmation'), findsOneWidget);
      expect(find.text('Status: cancelled'), findsOneWidget);
    },
  );
  Future<void> renewalReview(WidgetTester tester) async {
    await tap(tester, find.text('Review renewal'));
    await tap(tester, find.widgetWithText(FilledButton, 'Continue to Payment'));
    await tap(tester, find.widgetWithText(FilledButton, 'Review & Confirm'));
  }

  testWidgets(
    'renew review explains server terms and submits only on confirmation',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await renewalReview(tester);
      expect(billing.operations, isNot(contains('renew')));
      expect(find.text('Renewal price: ₹1,500.00'), findsOneWidget);
      expect(find.textContaining('Renewal starts:'), findsOneWidget);
      expect(find.textContaining('Renewal ends:'), findsOneWidget);
      expect(
        find.textContaining(
          'Renewal and any initial payment are saved together',
        ),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      expect(billing.operations, contains('renew'));
      expect(find.text('Renewal confirmed'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Done'));
      expect(find.text('Server confirmation'), findsOneWidget);
    },
  );
  testWidgets('empty and offline histories have explicit states and retry', (
    tester,
  ) async {
    await pump(tester);
    billing.empty = true;
    members.populated = false;
    members.historyRecords = [];
    container.invalidate(paymentHistoryProvider);
    container.invalidate(memberHistoryProvider);
    await tester.pumpAndSettle();
    expect(find.text('No current membership.'), findsOneWidget);
    await reveal(tester, find.text('No membership history.'));
    await reveal(tester, find.text('No successful payments.'));
    billing.failure = const BillingFailure('Safe offline message');
    container.invalidate(paymentHistoryProvider);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Safe offline message'));
    billing.failure = null;
    await tap(
      tester,
      find.ancestor(
        of: find.text('Retry'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    expect(find.text('No successful payments.'), findsOneWidget);
  });
  testWidgets('uncertain purchase disables retry and exposes history recheck', (
    tester,
  ) async {
    await pump(tester);
    await purchase(tester);
    await selectPlan(tester);
    await review(tester);
    billing.failure = const BillingFailure(
      'Verify history first',
      uncertain: true,
    );
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
    expect(find.text('Verify history first'), findsOneWidget);
    expect(billing.purchases.length, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review purchase'),
          )
          .onPressed,
      isNull,
    );
    billing.failure = null;
    await tap(
      tester,
      find.widgetWithText(
        OutlinedButton,
        'Check membership and payment history',
      ),
    );
    await tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Recheck membership and payments'),
    );
    expect(billing.purchases.length, 1);
    expect(find.text('Verify history first'), findsNothing);
  });
  testWidgets('double confirmation while pending submits once', (tester) async {
    await pump(tester);
    await purchase(tester);
    await selectPlan(tester);
    await review(tester);
    billing.writeGate = Completer<BillingResult>();
    final button = find.widgetWithText(FilledButton, 'Confirm purchase');
    await reveal(tester, button);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(billing.purchases.length, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    billing.writeGate!.complete(billingResult());
    await tester.pumpAndSettle();
    expect(find.text('Server confirmation'), findsOneWidget);
  });
  testWidgets(
    'gym switch refuses old membership context and makes no new reads',
    (tester) async {
      await pump(tester);
      final calls = billing.operations.length;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(find.textContaining('The gym context changed'), findsOneWidget);
      expect(billing.operations.length, calls);
    },
  );
  testWidgets(
    'logout from purchase returns to login without protected content',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await container.read(sessionControllerProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.welcome,
      );
      expect(find.text('Select an active plan'), findsNothing);
      expect(find.text('Who is signing in?'), findsOneWidget);
    },
  );
  testWidgets(
    'unauthenticated membership deep link redirects and login returns to dashboard',
    (tester) async {
      await pump(tester, authenticated: false);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.welcome,
      );
      expect(billing.operations, isEmpty);
      await container
          .read(sessionControllerProvider.notifier)
          .login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
      await tester.pumpAndSettle();
      // Authenticated admin route remains the dashboard unless explicitly selected.
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.dashboard,
      );
    },
  );
  testWidgets('non-admin deep link redirects before billing reads', (
    tester,
  ) async {
    await pump(tester, role: AuthRole.trainer);
    expect(billing.operations, isEmpty);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
  });
  testWidgets('membership route stays intact during session recovery', (
    tester,
  ) async {
    await pump(tester);
    await purchase(tester);
    await selectPlan(tester);
    final path = container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri;
    api.refreshGate = Completer();
    final pending = container.read(authRepositoryProvider).refreshSession();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri,
      path,
    );
    expect(find.text('Selected: Monthly'), findsNothing);
    api.refreshGate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Selected: Monthly'), findsOneWidget);
    expect(billing.purchases, isEmpty);
  });
  testWidgets('membership screen fits 320px phone and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await reveal(tester, find.text('Successful payment history'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'billing back navigation and shell destinations remain functional',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await tap(tester, find.byTooltip('Back to membership'));
      expect(find.text('Membership & payments'), findsOneWidget);
      await tap(tester, find.byTooltip('Back to member'));
      expect(find.text('Member details'), findsOneWidget);
      await tester.tap(find.text('Dashboard').last);
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.dashboard,
      );
    },
  );
  testWidgets('active plans show loading, empty, error and retry', (
    tester,
  ) async {
    await pump(tester);
    await purchase(tester);
    billing.planGate = Completer<BillingPage<MembershipPlan>>();
    container.invalidate(activePlansProvider);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    billing.planGate!.complete(BillingPage([], pagination(1, 0)));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No active membership plans. Create a plan before purchasing a membership.',
      ),
      findsOneWidget,
    );
    billing.planGate = null;
    billing.failure = const BillingFailure('Plans unavailable');
    container.invalidate(activePlansProvider);
    await tester.pumpAndSettle();
    expect(find.text('Plans unavailable'), findsOneWidget);
    billing.failure = null;
    await tap(
      tester,
      find.ancestor(
        of: find.text('Retry'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    expect(find.widgetWithText(ListTile, 'Monthly'), findsOneWidget);
  });
  Future<void> fillPlan(
    WidgetTester tester, {
    String name = 'Starter',
    String price = '0',
  }) async {
    for (final field in {
      'planName': name,
      'planDuration': '30',
      'planPrice': price,
    }.entries) {
      final finder = find.byKey(ValueKey(field.key));
      await reveal(tester, finder);
      await tester.enterText(finder, field.value);
    }
  }

  testWidgets(
    'empty purchase creates a plan and returns without automatic purchase',
    (tester) async {
      await pump(tester);
      billing.empty = true;
      await purchase(tester);
      expect(
        find.text(
          'No active membership plans. Create a plan before purchasing a membership.',
        ),
        findsOneWidget,
      );
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Create membership plan'),
      );
      expect(
        GoRouterState.of(tester.element(find.byType(PlanFormPage))).uri.path,
        '${AppRoutes.plans}/new',
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await fillPlan(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
      expect(find.text('Purchase membership'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.widgetWithText(ListTile, 'Starter'), findsOneWidget);
      expect(find.text('Selected: Starter'), findsNothing);
      expect(billing.purchases, isEmpty);
      expect(billing.planWrites.single['price'], 0);
      expect(billing.planWrites.single['status'], 'active');
    },
  );
  testWidgets('More opens management list with pagination and pull refresh', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Admin navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Membership Plans'));
    expect(find.text('₹1,500.00'), findsOneWidget);
    expect(find.text('≈1'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('Months (approx.)'), findsOneWidget);
    expect(find.text('Total days'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    billing.total = 21;
    container.invalidate(managedPlansProvider);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Next page'));
    await reveal(tester, find.text('Page 2 · 21 total'));
    expect(find.text('Page 2 · 21 total'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Admin navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    expect(find.text('Logout'), findsOneWidget);
  });
  testWidgets('create form validates duration and price before network', (
    tester,
  ) async {
    await pump(tester);
    container
        .read(appRouterProvider)
        .push('${AppRoutes.plans}/new?gymId=$gymA');
    await tester.pumpAndSettle();
    await fillPlan(tester, name: '😀' * 70, price: '1.001');
    await reveal(tester, find.byKey(const ValueKey('planDuration')));
    await tester.enterText(find.byKey(const ValueKey('planDuration')), '3651');
    await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
    expect(find.text('Enter 1–3650 whole days.'), findsOneWidget);
    expect(find.text('Use at most 120 characters.'), findsOneWidget);
    expect(
      find.text('Enter rupees with at most two decimal places.'),
      findsOneWidget,
    );
    expect(billing.planWrites, isEmpty);
  });
  testWidgets(
    'edit form loads server values, clears description and changes status',
    (tester) async {
      await pump(tester);
      billing.savedPlan = planJson()..['description'] = 'Old description';
      container
          .read(appRouterProvider)
          .push('${AppRoutes.plans}/$planId?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('planName')))
            .controller!
            .text,
        'Monthly',
      );
      await fillPlan(tester, name: 'Updated', price: '1500.01');
      await reveal(tester, find.byKey(const ValueKey('planDescription')));
      await tester.enterText(find.byKey(const ValueKey('planDescription')), '');
      await tap(tester, find.byKey(const ValueKey('planStatus')));
      await tester.tap(find.text('inactive').last);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
      expect(billing.planWrites.single, {
        'name': 'Updated',
        'durationDays': 30,
        'price': 150001,
        'status': 'inactive',
        'description': null,
      });
    },
  );
  testWidgets('plan list empty error retry and form safe failure', (
    tester,
  ) async {
    await pump(tester);
    billing.empty = true;
    container.read(appRouterProvider).go(AppRoutes.plans);
    await tester.pumpAndSettle();
    expect(
      find.text('No membership plans. Create your first plan.'),
      findsOneWidget,
    );
    billing.failure = const BillingFailure('Safe plan error');
    container.invalidate(managedPlansProvider);
    await tester.pumpAndSettle();
    expect(find.text('Safe plan error'), findsOneWidget);
    billing.failure = null;
    await tap(
      tester,
      find.ancestor(
        of: find.text('Retry'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    await tap(tester, find.text('New plan'));
    await fillPlan(tester);
    billing.failure = const BillingFailure('Duplicate plan name');
    await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
    expect(find.text('Duplicate plan name'), findsOneWidget);
    expect(find.text('Create membership plan'), findsOneWidget);
  });
  testWidgets(
    'plan form retains input through token refresh and logout redirects',
    (tester) async {
      await pump(tester);
      container
          .read(appRouterProvider)
          .push('${AppRoutes.plans}/new?gymId=$gymA');
      await tester.pumpAndSettle();
      await fillPlan(tester);
      final path = container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri;
      api.refreshGate = Completer<void>();
      final pending = container.read(authRepositoryProvider).refreshSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(appRouterProvider).routeInformationProvider.value.uri,
        path,
      );
      api.refreshGate!.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('planName')))
            .controller!
            .text,
        'Starter',
      );
      await container.read(sessionControllerProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(find.text('Who is signing in?'), findsOneWidget);
    },
  );
  testWidgets('four tabs select correctly and drawer retains the fifth route', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .length,
      4,
    );
    for (final entry in {
      'Dashboard': AppRoutes.dashboard,
      'Members': AppRoutes.members,
      'Trainers': AppRoutes.trainers,
      'Plans': AppRoutes.plans,
    }.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(entry.key),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        entry.value,
      );
      final labels = ['Dashboard', 'Members', 'Trainers', 'Plans'];
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        labels.indexOf(entry.key),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Admin navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider).state.uri.path, AppRoutes.more);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Owner profile'), findsOneWidget);
    expect(find.text('Membership Plans'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Logout'));
    expect(find.text('Who is signing in?'), findsOneWidget);
  });
  testWidgets('Plans create and edit back navigation return to plan list', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    // The tab label and the page title.
    expect(find.text('Plans'), findsNWidgets(2));
    await tap(tester, find.text('New plan'));
    expect(
      GoRouterState.of(tester.element(find.byType(PlanFormPage))).uri.path,
      '${AppRoutes.plans}/new',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.plans,
    );
    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit plan'));
    expect(
      GoRouterState.of(tester.element(find.byType(PlanFormPage))).uri.path,
      '${AppRoutes.plans}/$planId',
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await tap(tester, find.byTooltip('Back from plan form'));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.plans,
    );
  });
  testWidgets('canonical create and edit save return to refreshed plan list', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    final reads = billing.operations
        .where((op) => op.startsWith('plans:'))
        .length;
    await tap(tester, find.text('New plan'));
    await fillPlan(tester);
    await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.plans,
    );
    expect(find.text('Starter'), findsOneWidget);
    expect(
      billing.operations.where((op) => op.startsWith('plans:')).length,
      greaterThan(reads),
    );
    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit plan'));
    await fillPlan(tester, name: 'Changed plan', price: '10.01');
    await tap(tester, find.byKey(const ValueKey('planStatus')));
    await tester.tap(find.text('inactive').last);
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(FilledButton, 'Save plan'));
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.plans,
    );
    expect(find.text('Changed plan'), findsOneWidget);
    expect(find.text('₹10.01'), findsOneWidget);
    expect(find.textContaining('Inactive'), findsOneWidget);
    expect(billing.purchases, isEmpty);
  });
  testWidgets('Plans deep links remain admin-only', (tester) async {
    await pump(tester, authenticated: false, path: AppRoutes.plans);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.welcome,
    );
    expect(billing.operations, isEmpty);
    api.identity = adminIdentity(gyms: [gymA], role: AuthRole.trainer);
    await container
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
    container.read(appRouterProvider).go(AppRoutes.plans);
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(billing.operations, isEmpty);
  });
  testWidgets(
    'five destinations and Plans fit a 320px phone with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      // The tab label and the page title.
      expect(find.text('Plans'), findsNWidgets(2));
      expect(
        tester
            .widget<NavigationDestination>(
              find.byType(NavigationDestination).at(3),
            )
            .label,
        'Plans',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancelling a fully loaded renewal makes no mutation', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    await renewalReview(tester);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Member code: M001'), findsOneWidget);
    expect(find.textContaining('Existing end date:'), findsOneWidget);
    expect(find.text('Current plan duration: 30 days'), findsOneWidget);
    expect(find.text('To record now: ₹1,500.00'), findsOneWidget);
    expect(find.text('New membership balance: ₹0.00'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Not now'));
    expect(billing.renewals, isEmpty);
    expect(billing.operations.where((e) => e.startsWith('cancel:')), isEmpty);
    expect(find.text('Server confirmation'), findsNothing);
  });

  testWidgets(
    'renewal loading blocks confirmation and errors offer safe retry',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.text('Review renewal'));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Continue to Payment'),
      );
      billing.previewGate = Completer<RenewalPreview>();
      await reveal(
        tester,
        find.widgetWithText(FilledButton, 'Review & Confirm'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Review & Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Loading current renewal price and dates…'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Confirm Renewal'),
        findsNothing,
      );
      billing.previewGate!.completeError(
        const BillingFailure('Preview could not be loaded.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preview could not be loaded.'), findsOneWidget);
      expect(billing.renewals, isEmpty);
      billing.previewGate = null;
      await tap(
        tester,
        find.ancestor(
          of: find.text('Retry'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      );
      expect(find.text('Renewal price: ₹1,500.00'), findsOneWidget);
      expect(billing.renewals, isEmpty);
    },
  );

  testWidgets(
    'stale terms require reviewing new price and a second explicit confirmation',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await renewalReview(tester);
      billing.failure = const BillingFailure(
        'Review changed terms.',
        code: 'RENEWAL_PREVIEW_CHANGED',
        httpStatus: 409,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      expect(billing.renewals.length, 1);
      expect(find.textContaining('Review the current plan'), findsOneWidget);
      billing.failure = null;
      billing.previewJson = renewalPreviewJson()
        ..['terms'] = {
          ...renewalPreviewJson()['terms'] as Map<String, dynamic>,
          'pricePaise': 180000,
        }
        ..['outstandingBalancePaise'] = 180000;
      expect(RenewalPreview.fromJson(billing.previewJson!).pricePaise, 180000);
      await tap(
        tester,
        find.ancestor(
          of: find.text('Retry'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      );
      expect(find.text('Renewal price: ₹1,800.00'), findsOneWidget);
      expect(billing.renewals.length, 1);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      expect(billing.renewals.last!.pricePaise, 180000);
      expect(find.text('Renewal confirmed'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Done'));
      expect(find.text('Server confirmation'), findsOneWidget);
    },
  );

  testWidgets('confirmation duplicate taps do not create a second renewal', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    await renewalReview(tester);
    billing.writeGate = Completer<BillingResult>();
    final button = find.widgetWithText(FilledButton, 'Confirm Renewal');
    await reveal(tester, button);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(billing.renewals.length, 1);
    expect(find.text('Confirming renewal…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Not now'))
          .onPressed,
      isNull,
    );
    billing.writeGate!.complete(billingResult(renewed: true));
    await tester.pumpAndSettle();
    expect(find.text('Renewal confirmed'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(find.text('Server confirmation'), findsOneWidget);
  });

  testWidgets('scope change invalidates an open renewal preview', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    await renewalReview(tester);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The account or gym changed. Close this preview'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Confirm Renewal'), findsNothing);
    expect(billing.renewals, isEmpty);
  });

  testWidgets('free renewal preview fits narrow screen and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await detail(tester);
    billing.previewJson = renewalPreviewJson()
      ..['terms'] = {
        ...renewalPreviewJson()['terms'] as Map<String, dynamic>,
        'pricePaise': 0,
      }
      ..['outstandingBalancePaise'] = 0;
    expect(RenewalPreview.fromJson(billing.previewJson!).pricePaise, 0);
    await renewalReview(tester);
    expect(find.text('Renewal price: ₹0.00'), findsOneWidget);
    expect(
      find.textContaining('Free plan. No payment is due.'),
      findsOneWidget,
    );
    await reveal(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.widgetWithText(TextButton, 'Not now'));
    expect(billing.renewals, isEmpty);
  });
  testWidgets(
    'ambiguous renewal blocks another confirmation and directs history review',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await renewalReview(tester);
      billing.failure = const BillingFailure(
        'The outcome is uncertain.',
        uncertain: true,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      expect(billing.renewals.length, 1);
      expect(find.textContaining('Do not collect money again'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Confirm Renewal'),
        findsNothing,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Not now'));
      await tap(tester, find.text('Review renewal'));
      expect(find.textContaining('Recover saved renewal'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, 'Not now'));
      expect(billing.renewals.length, 1);
    },
  );
  testWidgets('in-flight renewal scope change never displays a stale success', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    await renewalReview(tester);
    billing.writeGate = Completer<BillingResult>();
    await reveal(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Renewal'));
    await tester.pump();
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await tester.pump();
    billing.writeGate!.complete(billingResult(renewed: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The account or gym changed. Close this preview'),
      findsOneWidget,
    );
    expect(find.text('Server confirmation'), findsNothing);
    expect(billing.renewals.length, 1);
    expect(find.widgetWithText(FilledButton, 'Confirm Renewal'), findsNothing);
    await tap(tester, find.widgetWithText(TextButton, 'Not now'));
    expect(find.text('Server confirmation'), findsNothing);
  });
  Future<void> cancellation(WidgetTester tester) =>
      tap(tester, find.widgetWithText(TextButton, 'Cancel membership'));

  testWidgets(
    'cancellation shows verified member and membership-specific dues with readable dates',
    (tester) async {
      await pump(tester);
      members.paidPaise = 100000;
      members.balancePaise = 50000;
      await detail(tester);
      await cancellation(tester);
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(find.text('Monthly'), findsWidgets);
      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.textContaining('End date: Tue, Mar 31'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      expect(find.text('Total paid: ₹1,000.00'), findsOneWidget);
      expect(
        find.textContaining('does not collect, waive or delete it'),
        findsOneWidget,
      );
      expect(
        find.textContaining('excluded from current outstanding dues'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot record any further payments'),
        findsOneWidget,
      );
      expect(find.textContaining('No refund is created'), findsOneWidget);
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')),
        isEmpty,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, 'Keep Membership'));
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')),
        isEmpty,
      );
      expect(find.text('Cancel membership?'), findsNothing);
    },
  );

  testWidgets(
    'fully paid cancellation preview shows zero without implying debt',
    (tester) async {
      await pump(tester);
      members.paidPaise = 150000;
      members.balancePaise = 0;
      await detail(tester);
      await cancellation(tester);
      // Within the sheet; the page behind shows its own balance.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('₹0.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Total paid: ₹1,500.00'), findsOneWidget);
      expect(
        find.textContaining('There is no unpaid balance to collect.'),
        findsOneWidget,
      );
      expect(find.textContaining('The unpaid'), findsNothing);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Keep Membership'));
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'cancellation reload hides cached balance and disables confirm during loading',
    (tester) async {
      await pump(tester);
      await detail(tester);
      members.detailGate = Completer<MembershipDetail>();
      await reveal(
        tester,
        find.widgetWithText(TextButton, 'Cancel membership'),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel membership'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Checking membership details and saved balance…'),
        findsOneWidget,
      );
      expect(find.text('Outstanding balance'), findsNothing);
      expect(find.text('₹0.00'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Cancellation'),
            )
            .onPressed,
        isNull,
      );
      members.detailGate!.completeError(
        const MemberFailure('Saved balance is unavailable.'),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CancellationConfirmationSheet),
          matching: find.text('Saved balance is unavailable.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Outstanding balance'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Cancellation'),
            )
            .onPressed,
        isNull,
      );
      members.detailGate = null;
      await tap(
        tester,
        find.descendant(
          of: find.byType(CancellationConfirmationSheet),
          matching: find.ancestor(
            of: find.text('Retry'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        ),
      );
      expect(find.text('Outstanding balance'), findsOneWidget);
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')),
        isEmpty,
      );
    },
  );

  testWidgets('an inconsistent saved balance cannot enable cancellation', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    members.balancePaise =
        0; // Still only 303 paise paid against a 150000 price.
    await cancellation(tester);
    expect(
      find.textContaining('could not be verified. Reload before cancelling.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('₹0.00'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm Cancellation'),
          )
          .onPressed,
      isNull,
    );
    members.balancePaise = 149697;
    await tap(
      tester,
      find.descendant(
        of: find.byType(CancellationConfirmationSheet),
        matching: find.ancestor(
          of: find.text('Retry'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      ),
    );
    expect(find.text('Outstanding balance'), findsOneWidget);
    expect(billing.operations.where((op) => op.startsWith('cancel:')), isEmpty);
  });

  testWidgets(
    'unknown member identity blocks cancellation without exposing a false balance',
    (tester) async {
      await pump(tester);
      await detail(tester);
      final scope = scopeFor(container.read(adminGymProvider)!, memberId);
      final override = container.listen(
        memberProfileProvider(scope),
        (_, _) {},
      );
      addTearDown(override.close);
      members.failure = const MemberFailure('Member details are unavailable.');
      await cancellation(tester);
      expect(find.text('Member details are unavailable.'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Cancellation'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Outstanding balance'), findsNothing);
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'cancellation double taps send once and successful response refreshes details',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await cancellation(tester);
      final before = members.operations
          .where((op) => op.startsWith('membership:'))
          .length;
      billing.writeGate = Completer<BillingResult>();
      final confirm = find.widgetWithText(FilledButton, 'Confirm Cancellation');
      await reveal(tester, confirm);
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')).length,
        1,
      );
      expect(find.text('Cancelling membership…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Keep Membership'),
            )
            .onPressed,
        isNull,
      );
      members.cancelled = true;
      billing.writeGate!.complete(billingResult(cancelled: true));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Membership cancelled. History has been kept. No refund was made.',
        ),
        findsOneWidget,
      );
      expect(find.text('Server confirmation'), findsOneWidget);
      expect(find.text('Cancel membership?'), findsNothing);
      expect(find.text('Cancel membership'), findsNothing);
      expect(find.text('Record Payment'), findsNothing);
      expect(
        members.operations.where((op) => op.startsWith('membership:')).length,
        greaterThan(before),
      );
      // Cancellation does not zero or remove historical payment totals.
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('₹3.03'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
      expect(find.text('₹1,496.97'), findsOneWidget);
    },
  );

  testWidgets(
    'definite cancellation rejection stays open with clear failure and no success',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await cancellation(tester);
      billing.failure = const BillingFailure(
        'Cancellation was refused. Refresh membership history.',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Confirm Cancellation'),
      );
      expect(
        find.text('Cancellation was refused. Refresh membership history.'),
        findsWidgets,
      );
      expect(find.text('Cancel membership?'), findsOneWidget);
      expect(find.text('Server confirmation'), findsNothing);
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')).length,
        1,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, 'Keep Membership'));
      expect(find.text('Server confirmation'), findsNothing);
    },
  );

  testWidgets(
    'ambiguous cancellation blocks resubmission and directs history review',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await cancellation(tester);
      billing.failure = const BillingFailure(
        'The outcome is uncertain.',
        uncertain: true,
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Confirm Cancellation'),
      );
      expect(find.textContaining('Do not submit again.'), findsOneWidget);
      expect(find.text('Server confirmation'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Cancellation'),
            )
            .onPressed,
        isNull,
      );
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')).length,
        1,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, 'Keep Membership'));
      expect(find.text('Check membership and payment history'), findsOneWidget);
      await reveal(
        tester,
        find.widgetWithText(TextButton, 'Cancel membership'),
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Cancel membership'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'scope change blocks an open cancellation and stale completion cannot publish success',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await cancellation(tester);
      billing.writeGate = Completer<BillingResult>();
      await reveal(
        tester,
        find.widgetWithText(FilledButton, 'Confirm Cancellation'),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm Cancellation'),
      );
      await tester.pump();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pump();
      billing.writeGate!.complete(billingResult(cancelled: true));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'The account or gym changed. Close this confirmation',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Cancellation'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Server confirmation'), findsNothing);
      expect(
        billing.operations.where((op) => op.startsWith('cancel:')).length,
        1,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, 'Keep Membership'));
      expect(find.text('Server confirmation'), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'cancellation preview fits narrow screen and enlarged text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pump(tester);
        await detail(tester);
        await cancellation(tester);
        await reveal(
          tester,
          find.widgetWithText(FilledButton, 'Confirm Cancellation'),
        );
        expect(tester.takeException(), isNull);
        await tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Keep Membership'),
        );
        expect(
          billing.operations.where((op) => op.startsWith('cancel:')),
          isEmpty,
        );
      },
    );
  }
  Future<void> paymentChoice(WidgetTester tester, String label) async {
    await tap(
      tester,
      find.byType(DropdownButtonFormField<RenewalPaymentChoice>),
    );
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renewal preselects previous active plan and full payment records actual receipt',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await renewalReview(tester);
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsNothing);
      expect(find.text('To record now: ₹1,500.00'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      final repository =
          container.read(renewalRepositoryProvider) as FakeRenewalRepository;
      expect(repository.requests.single.receivedPaise, 150000);
      expect(repository.committed.values.single.payment!.amountPaise, 150000);
      expect(find.text('Renewal confirmed'), findsOneWidget);
      expect(find.text('New membership balance: ₹0.00'), findsOneWidget);
    },
  );
  testWidgets(
    'different plan partial payment updates balance and preserves previous dues',
    (tester) async {
      await pump(tester);
      await detail(tester);
      billing.extraPlans.add({
        ...planJson(),
        'id': '000000000000000000000099',
        'name': 'Quarterly',
        'durationDays': 90,
        'price': 60000,
      });
      await tap(tester, find.text('Review renewal'));
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      await tap(tester, find.widgetWithText(ListTile, 'Quarterly'));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Continue to Payment'),
      );
      await paymentChoice(tester, 'Partial payment');
      await tester.enterText(
        find.byKey(const ValueKey('renewalAmount')),
        '200.01',
      );
      await tester.pump();
      expect(
        find.text('To record: ₹200.01 · Remaining: ₹399.99'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Review & Confirm'));
      expect(find.text('Current plan duration: 90 days'), findsOneWidget);
      expect(
        find.text('Previous membership balance (separate): ₹1,496.97'),
        findsOneWidget,
      );
      expect(find.text('New membership balance: ₹399.99'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      final repository =
          container.read(renewalRepositoryProvider) as FakeRenewalRepository;
      expect(
        repository.requests.single.body['planId'],
        '000000000000000000000099',
      );
      expect(repository.committed.values.single.payment!.amountPaise, 20001);
    },
  );
  testWidgets(
    'Pay later clears stale reference and amount and omits initial payment',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.text('Review renewal'));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Continue to Payment'),
      );
      await paymentChoice(tester, 'Partial payment');
      await tester.enterText(
        find.byKey(const ValueKey('renewalAmount')),
        '200',
      );
      await tester.enterText(
        find.byKey(const ValueKey('renewalReference')),
        'REF-TEST',
      );
      await paymentChoice(tester, 'Pay later');
      expect(
        find.text('To record: ₹0.00 · Remaining: ₹1,500.00'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Review & Confirm'));
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm Renewal'));
      final repository =
          container.read(renewalRepositoryProvider) as FakeRenewalRepository;
      expect(repository.requests.single.body.containsKey('payment'), false);
      expect(repository.committed.values.single.payment, isNull);
      expect(find.text('New membership balance: ₹1,500.00'), findsOneWidget);
    },
  );
  testWidgets(
    'invalid partial amounts and digital reference block review without sending',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.text('Review renewal'));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Continue to Payment'),
      );
      await paymentChoice(tester, 'Partial payment');
      for (final amount in ['0', '-1', '1500.01']) {
        await reveal(tester, find.byKey(const ValueKey('renewalAmount')));
        await tester.enterText(
          find.byKey(const ValueKey('renewalAmount')),
          amount,
        );
        await tap(
          tester,
          find.widgetWithText(FilledButton, 'Review & Confirm'),
        );
        expect(
          find.widgetWithText(FilledButton, 'Confirm Renewal'),
          findsNothing,
        );
      }
      await reveal(tester, find.byKey(const ValueKey('renewalAmount')));
      await tester.enterText(
        find.byKey(const ValueKey('renewalAmount')),
        '500',
      );
      await tap(tester, find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'Review & Confirm'));
      expect(find.text('A payment reference is required.'), findsOneWidget);
      expect(billing.renewals, isEmpty);
    },
  );
  testWidgets('plan loading errors and empty results prevent unsafe renewal', (
    tester,
  ) async {
    await pump(tester);
    await detail(tester);
    billing.empty = true;
    await tap(tester, find.text('Review renewal'));
    expect(find.textContaining('No active membership plans.'), findsOneWidget);
    expect(billing.renewals, isEmpty);
    await tap(tester, find.widgetWithText(TextButton, 'Not now'));
    billing.empty = false;
    billing.failure = const BillingFailure('Plans unavailable.');
    await tap(tester, find.text('Review renewal'));
    expect(find.text('Plans unavailable.'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue to Payment'),
          )
          .onPressed,
      isNull,
    );
    expect(billing.renewals, isEmpty);
  });
  Future<void> enterInitialAmount(WidgetTester tester, String amount) async {
    await reveal(tester, find.byKey(const ValueKey('paymentAmount')));
    await tester.enterText(find.byKey(const ValueKey('paymentAmount')), amount);
    await tester.pumpAndSettle();
  }

  for (final amount in ['-1', '1500.01']) {
    testWidgets(
      'purchase rejects initial amount $amount near field before review',
      (tester) async {
        await pump(tester);
        await purchase(tester);
        await selectPlan(tester);
        await tap(tester, find.byType(SwitchListTile));
        await enterInitialAmount(tester, amount);
        await review(tester);
        final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('paymentAmount')),
        );
        expect(field.validator!(amount), isNotNull);
        expect(
          find.text(
            amount == '-1'
                ? 'The initial payment cannot be negative.'
                : 'Payment cannot exceed the selected plan price.',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Confirm purchase'),
          findsNothing,
        );
        expect(billing.purchases, isEmpty);
      },
    );
  }
  testWidgets(
    'purchase full price shortcut uses exact paise and zero balance',
    (tester) async {
      await pump(tester);
      billing.savedPlan = planJson()..['price'] = 150001;
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await tap(tester, find.widgetWithText(TextButton, 'Use full plan price'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        '1500.01',
      );
      expect(
        find.text('Initial payment: ₹1,500.01 · Remaining balance: ₹0.00'),
        findsOneWidget,
      );
      await review(tester);
      expect(find.text('Remaining balance: ₹0.00'), findsOneWidget);
      expect(find.text('Server confirmation'), findsNothing);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment!.amountPaise, 150001);
      expect(find.text('Server confirmation'), findsOneWidget);
    },
  );
  testWidgets(
    'purchase partial payment shows immediate exact outstanding balance',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '500.01');
      expect(
        find.text('Initial payment: ₹500.01 · Remaining balance: ₹999.99'),
        findsOneWidget,
      );
      await review(tester);
      expect(find.text('Remaining balance: ₹999.99'), findsOneWidget);
      expect(find.text('Payment to record: ₹500.01 · Cash'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment!.amountPaise, 50001);
      expect(billing.purchases.single.payment!.reference, isEmpty);
    },
  );
  testWidgets(
    'zero initial purchase omits payment and needs no digital reference',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '0');
      await tap(tester, find.byKey(const ValueKey('paymentMethod')));
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('paymentReference')),
            )
            .enabled,
        false,
      );
      await review(tester);
      expect(find.text('No payment will be recorded.'), findsOneWidget);
      expect(find.text('Remaining balance: ₹1,500.00'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment, isNull);
      expect(
        billing.purchases.single.toJson(memberId).containsKey('payment'),
        false,
      );
    },
  );
  testWidgets('pay later switch clears amount method and reference', (
    tester,
  ) async {
    await pump(tester);
    await purchase(tester);
    await selectPlan(tester);
    await tap(tester, find.byType(SwitchListTile));
    await enterInitialAmount(tester, '500');
    await tap(tester, find.byKey(const ValueKey('paymentMethod')));
    await tester.tap(find.text('UPI').last);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('paymentReference')));
    await tester.enterText(
      find.byKey(const ValueKey('paymentReference')),
      'TEST-REF',
    );
    await tap(tester, find.byType(SwitchListTile));
    await review(tester);
    expect(find.text('No payment will be recorded.'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Edit purchase'));
    await tap(tester, find.byType(SwitchListTile));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('paymentReference')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('Cash'), findsOneWidget);
  });
  testWidgets(
    'free plan clears prior positive payment and cannot record money',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '500');
      billing.extraPlans.add({
        ...planJson(),
        'id': '000000000000000000000099',
        'name': 'Free plan',
        'price': 0,
      });
      container.invalidate(activePlansProvider);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(ListTile, 'Free plan'));
      expect(
        find.text('Free plan · ₹0.00. No initial payment is required.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paymentAmount')), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await review(tester);
      expect(find.text('Remaining balance: ₹0.00'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment, isNull);
      expect(billing.purchases.single.planId, '000000000000000000000099');
    },
  );
  testWidgets(
    'lower-price plan change clears incompatible payment and requires new review',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '1000');
      await review(tester);
      await tap(tester, find.widgetWithText(TextButton, 'Edit purchase'));
      billing.extraPlans.add({
        ...planJson(),
        'id': '000000000000000000000099',
        'name': 'Starter',
        'price': 70000,
      });
      container.invalidate(activePlansProvider);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(ListTile, 'Starter'));
      expect(
        find.textContaining(
          'The previous payment amount is not valid for this plan.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        isEmpty,
      );
      await review(tester);
      expect(
        find.widgetWithText(FilledButton, 'Confirm purchase'),
        findsNothing,
      );
      expect(billing.purchases, isEmpty);
      await enterInitialAmount(tester, '200.01');
      expect(
        find.textContaining(
          'The previous payment amount is not valid for this plan.',
        ),
        findsNothing,
      );
      await review(tester);
      expect(find.text('Remaining balance: ₹499.99'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.planId, '000000000000000000000099');
      expect(billing.purchases.single.payment!.amountPaise, 20001);
    },
  );
  testWidgets(
    'reselecting repriced plan refreshes its limit and clears overpayment',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '1000');
      billing.savedPlan = planJson()..['price'] = 80000;
      container.invalidate(activePlansProvider);
      await tester.pumpAndSettle();
      await selectPlan(tester);
      expect(find.text('Plan price: ₹800.00'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        isEmpty,
      );
      expect(billing.purchases, isEmpty);
      await enterInitialAmount(tester, '800.01');
      await review(tester);
      expect(
        find.text('Payment cannot exceed the selected plan price.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Confirm purchase'),
        findsNothing,
      );
    },
  );
  for (final method in ['UPI', 'Bank transfer', 'Card']) {
    testWidgets('positive purchase with $method requires a valid reference', (
      tester,
    ) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '500');
      await tap(tester, find.byKey(const ValueKey('paymentMethod')));
      await tester.tap(find.text(method).last);
      await tester.pumpAndSettle();
      await review(tester);
      expect(find.text('A payment reference is required.'), findsOneWidget);
      expect(billing.purchases, isEmpty);
      await reveal(tester, find.byKey(const ValueKey('paymentReference')));
      await tester.enterText(
        find.byKey(const ValueKey('paymentReference')),
        'REF-TEST',
      );
      await review(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(billing.purchases.single.payment!.reference, 'REF-TEST');
    });
  }
  testWidgets(
    'known purchase failure preserves draft and shows no false success',
    (tester) async {
      await pump(tester);
      await purchase(tester);
      await selectPlan(tester);
      await tap(tester, find.byType(SwitchListTile));
      await enterInitialAmount(tester, '500');
      await review(tester);
      billing.failure = const BillingFailure(
        'Purchase was refused. Check membership history.',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm purchase'));
      expect(
        find.text('Purchase was refused. Check membership history.'),
        findsOneWidget,
      );
      expect(find.text('Server confirmation'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        '500',
      );
      expect(billing.purchases.length, 1);
    },
  );
}
