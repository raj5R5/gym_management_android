import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_management_app/features/memberships/presentation/plans_page.dart'
    show PlanFormPage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    members = ActiveMembershipMemberRepository()..populated = true;
    api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
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
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GymApp()),
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
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Membership & payments'),
      );
      expect(find.text('Membership & payments'), findsOneWidget);
      expect(find.text('Current membership'), findsOneWidget);
      expect(find.textContaining('Balance: ₹1,496.97'), findsOneWidget);
      await reveal(tester, find.text('Successful payment history'));
      expect(find.text('₹3.03 · Cash'), findsOneWidget);
      expect(
        billing.operations.where((e) => e.startsWith('payments')).length,
        1,
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
    expect(find.textContaining('2026-03-01 → 2026-03-31'), findsOneWidget);
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
      expect(find.text('Successful payment: ₹3.03 · UPI'), findsOneWidget);
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
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Cancel membership'),
      );
      expect(billing.operations.where((e) => e.startsWith('cancel')), isEmpty);
      expect(find.textContaining('No refund is created'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('cancellationReason')));
      await tester.enterText(
        find.byKey(const ValueKey('cancellationReason')),
        'Requested',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Confirm cancellation'),
      );
      expect(billing.operations, contains('cancel:Requested'));
      expect(find.text('Server confirmation'), findsOneWidget);
      expect(find.text('Status: cancelled'), findsOneWidget);
    },
  );
  testWidgets(
    'renew review explains server terms and submits only on confirmation',
    (tester) async {
      await pump(tester);
      await detail(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Review renewal'));
      expect(billing.operations, isNot(contains('renew')));
      expect(
        find.textContaining('No payment is recorded by renewal'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm renewal'));
      expect(billing.operations, contains('renew'));
      expect(find.text('Server confirmation'), findsOneWidget);
    },
  );
  testWidgets('empty and offline histories have explicit states and retry', (
    tester,
  ) async {
    await pump(tester);
    billing.empty = true;
    members.populated = false;
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
    await tap(tester, find.widgetWithText(TextButton, 'Retry'));
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
        AppRoutes.login,
      );
      expect(find.text('Select an active plan'), findsNothing);
      expect(find.text('Sign in to your account'), findsOneWidget);
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
        AppRoutes.login,
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
    await tap(tester, find.widgetWithText(TextButton, 'Retry'));
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
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(OutlinedButton, 'Membership Plans'));
    expect(find.textContaining('30 days · ₹1,500.00 · Active'), findsOneWidget);
    billing.total = 21;
    container.invalidate(managedPlansProvider);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Next page'));
    expect(find.text('Page 2 · 21 total'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').last);
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
    await tap(tester, find.widgetWithText(TextButton, 'Retry'));
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Create membership plan'),
    );
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
      expect(find.text('Sign in to your account'), findsOneWidget);
    },
  );
  testWidgets(
    'five first-class admin destinations route and select correctly',
    (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        5,
      );
      for (final entry in {
        'Dashboard': AppRoutes.dashboard,
        'Members': AppRoutes.members,
        'Trainers': AppRoutes.trainers,
        'Plans': AppRoutes.plans,
        'More': AppRoutes.more,
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
        final labels = ['Dashboard', 'Members', 'Trainers', 'Plans', 'More'];
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          labels.indexOf(entry.key),
        );
        expect(tester.takeException(), isNull);
      }
      await tap(tester, find.widgetWithText(FilledButton, 'Logout'));
      expect(find.text('Sign in to your account'), findsOneWidget);
    },
  );
  testWidgets('Plans create and edit back navigation return to plan list', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.text('Membership Plans'), findsOneWidget);
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Create membership plan'),
    );
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
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Create membership plan'),
    );
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
    expect(find.textContaining('₹10.01 · Inactive'), findsOneWidget);
    expect(billing.purchases, isEmpty);
  });
  testWidgets('Plans deep links remain admin-only', (tester) async {
    await pump(tester, authenticated: false, path: AppRoutes.plans);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.login,
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
      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      expect(find.text('Membership Plans'), findsOneWidget);
      expect(find.text('Plans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
