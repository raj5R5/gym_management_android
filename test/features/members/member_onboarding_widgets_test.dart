import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'dart:ui' show Tristate;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/members/presentation/member_onboarding_page.dart';
import 'package:gym_management_app/features/members/presentation/onboarding_review_step.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/providers/plan_providers.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import '../memberships/billing_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';

void main() {
  Future<({ProviderContainer scope, FakeMemberRepository members})> pumpWizard(
    WidgetTester tester, {
    List<String> gyms = const [gymA],
    FakeMembershipRepository? billing,
    FakeAuthApi? authApi,
  }) async {
    final members = FakeMemberRepository();
    final scope = ProviderContainer(
      overrides: [
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        ),
        authApiServiceProvider.overrideWithValue(
          authApi ?? (FakeAuthApi()..identity = adminIdentity(gyms: gyms)),
        ),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()..value = syntheticCredential(),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        // These tests count wizard plan requests. Dashboard's independent
        // pagination-total read is exercised in the dashboard tests.
        activePlanCountProvider.overrideWith((ref) => 0),
        memberRepositoryProvider.overrideWithValue(members),
        membershipRepositoryProvider.overrideWithValue(
          billing ?? FakeMembershipRepository(),
        ),
        memberOnboardingRepositoryProvider.overrideWithValue(
          FakeOnboardingRepository(),
        ),
        pendingOnboardingStoreProvider.overrideWithValue(
          SecurePendingOnboardingStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const GymApp(animateDecorations: false),
      ),
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).go('${AppRoutes.members}/new?gymId=$gymA');
    await tester.pumpAndSettle();
    return (scope: scope, members: members);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await reveal(tester, find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  // Date of birth is chosen with the date picker in typed-input mode.
  Future<void> pickBirthDate(WidgetTester tester, String typed) async {
    final field = find.byKey(const ValueKey('dateOfBirth'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(field), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextField),
      ),
      typed,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    for (final entry in {
      'firstName': 'Alex',
      'lastName': 'River',
      'phone': '9876543210',
    }.entries) {
      final finder = find.byKey(ValueKey(entry.key));
      await reveal(tester, finder);
      await tester.enterText(finder, entry.value);
    }
    await pickBirthDate(tester, '01/02/2000');
  }

  String title(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('onboarding-step-title'))).data!;
  String value(WidgetTester tester, String field) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(field)),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  bool continueEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Continue'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed !=
      null;

  testWidgets(
    'exit dialog fits a narrow phone with keyboard and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final result = await pumpWizard(tester);
      await reveal(tester, find.byKey(const ValueKey('firstName')));
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Unsaved',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      result.scope.read(appRouterProvider).go(AppRoutes.members);
      await tester.pumpAndSettle();
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Discard changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(value(tester, 'firstName'), 'Unsaved');
    },
  );

  testWidgets('unchanged registration exits without a warning', (tester) async {
    final result = await pumpWizard(tester);
    result.scope.read(appRouterProvider).go(AppRoutes.members);
    await tester.pumpAndSettle();
    expect(find.byType(MemberOnboardingPage), findsNothing);
    expect(find.text('Discard unsaved changes?'), findsNothing);
  });

  testWidgets('reverting typed changes restores a clean registration', (
    tester,
  ) async {
    final result = await pumpWizard(tester);
    await tester.enterText(find.byKey(const ValueKey('firstName')), 'Alex');
    await tester.enterText(find.byKey(const ValueKey('firstName')), '');
    result.scope.read(appRouterProvider).go(AppRoutes.members);
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(find.byType(MemberOnboardingPage), findsNothing);
  });

  for (final exit in ['system', 'Back', 'tab', 'drawer', 'route']) {
    testWidgets(
      'dirty registration protects $exit and preserves Keep editing',
      (tester) async {
        final result = await pumpWizard(tester);
        await tester.enterText(
          find.byKey(const ValueKey('firstName')),
          'Unsaved',
        );
        await tester.pumpAndSettle();
        Future<void> leave() async {
          switch (exit) {
            case 'system':
              await tester.binding.handlePopRoute();
            case 'Back':
              await tap(tester, 'Back');
            case 'tab':
              await tester.tap(
                find.descendant(
                  of: find.byType(NavigationBar),
                  matching: find.text('Dashboard'),
                ),
              );
            case 'drawer':
              await tester.tap(find.byTooltip('Admin navigation'));
              await tester.pumpAndSettle();
              await tester.tap(
                find.descendant(
                  of: find.byType(Drawer),
                  matching: find.text('Dashboard'),
                ),
              );
            case 'route':
              result.scope.read(appRouterProvider).go(AppRoutes.dashboard);
          }
          await tester.pumpAndSettle();
        }

        await leave();
        expect(find.text('Discard unsaved changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(value(tester, 'firstName'), 'Unsaved');
        await leave();
        await tester.tap(find.text('Discard changes'));
        await tester.pumpAndSettle();
        expect(find.byType(MemberOnboardingPage), findsNothing);
      },
    );
  }

  testWidgets(
    'repeated tab exits open one dialog and perform one chosen exit',
    (tester) async {
      await pumpWizard(tester);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Unsaved',
      );
      await tester.pumpAndSettle();
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      nav.onDestinationSelected!(0);
      await tester.pump();
      nav.onDestinationSelected!(2);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(value(tester, 'firstName'), 'Unsaved');
    },
  );

  testWidgets(
    'gym selection requires discard and Keep editing restores selector',
    (tester) async {
      final result = await pumpWizard(tester, gyms: [gymA, gymB]);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Unsaved',
      );
      await tester.pumpAndSettle();
      Future<void> changeGym() async {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gym $gymB').last);
        await tester.pumpAndSettle();
      }

      await changeGym();
      expect(result.scope.read(adminGymProvider)!.gymId, gymA);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(value(tester, 'firstName'), 'Unsaved');
      expect(result.scope.read(adminGymProvider)!.gymId, gymA);
      await changeGym();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(result.scope.read(adminGymProvider)!.gymId, gymB);
    },
  );

  for (final savePlan in [false, true]) {
    testWidgets(
      'empty plans preserve draft after ${savePlan ? 'saving' : 'cancelling'} plan creation',
      (tester) async {
        final billing = FakeMembershipRepository()..empty = true;
        await pumpWizard(tester, billing: billing);
        await fill(tester);
        await tap(tester, 'Continue');
        await tap(tester, 'Create membership plan');
        expect(find.text('Discard unsaved changes?'), findsNothing);
        expect(billing.planWrites, isEmpty);
        if (savePlan) {
          for (final field in {
            'planName': 'Pilot plan',
            'planDuration': '30',
            'planPrice': '1500',
          }.entries) {
            await reveal(tester, find.byKey(ValueKey(field.key)));
            await tester.enterText(
              find.byKey(ValueKey(field.key)),
              field.value,
            );
          }
          await tap(tester, 'Save plan');
          expect(billing.planWrites, hasLength(1));
          expect(find.text('Pilot plan'), findsOneWidget);
        } else {
          await tester.tap(find.byTooltip('Back from plan form'));
          await tester.pumpAndSettle();
          expect(billing.planWrites, isEmpty);
        }
        expect(title(tester), 'Membership Plan');
        expect(
          billing.operations.where((call) => call == 'plans:$gymA:1').length,
          greaterThanOrEqualTo(2),
        );
        await tap(tester, 'Back');
        expect(value(tester, 'firstName'), 'Alex');
        expect(value(tester, 'phone'), '9876543210');
      },
    );
  }

  testWidgets(
    'four-step shell updates progress without submitting before confirmation',
    (tester) async {
      final result = await pumpWizard(tester);
      final semantics = tester.ensureSemantics();
      expect(find.byType(MemberOnboardingPage), findsOneWidget);
      expect(title(tester), 'Member Details');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Step 1: Member Details'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      semantics.dispose();
      await fill(tester);
      await tap(tester, 'Continue');
      expect(title(tester), 'Membership Plan');
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      expect(title(tester), 'Payment');
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      // The server numbers the member; the wizard never asks for a code.
      expect(find.textContaining('Member code'), findsNothing);
      await reveal(tester, find.text('Confirm registration'));
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Confirm registration'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text(onboardingConfirmationMessage), findsOneWidget);
      expect(result.members.writes, isEmpty);
    },
  );
  testWidgets(
    'Back and system back preserve entered fields and optional gender',
    (tester) async {
      await pumpWizard(tester);
      await fill(tester);
      await reveal(tester, find.text('Not specified'));
      await tester.tap(find.text('Not specified'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('female').last);
      await tester.pumpAndSettle();
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(title(tester), 'Membership Plan');
      await tap(tester, 'Back');
      expect(title(tester), 'Member Details');
      expect(value(tester, 'firstName'), 'Alex');
      expect(value(tester, 'lastName'), 'River');
      expect(value(tester, 'phone'), '9876543210');
      expect(value(tester, 'dateOfBirth'), 'Jan 2, 2000');
      expect(find.text('female'), findsOneWidget);
    },
  );
  testWidgets('required fields are validated before Continue', (tester) async {
    final result = await pumpWizard(tester);
    await tap(tester, 'Continue');
    expect(title(tester), 'Member Details');
    expect(find.text('Enter 1–80 characters.'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('memberCode')), findsNothing);
    expect(find.text('Enter a phone number with 7–15 digits.'), findsOneWidget);
    expect(result.members.writes, isEmpty);
  });
  // Impossible dates cannot be picked; format validation is covered in
  // birth_date_field_test.dart. Under-18 dates must still block the wizard.
  testWidgets('under-18 birth date cannot advance', (tester) async {
    await pumpWizard(tester);
    await fill(tester);
    final year = DateTime.now().year - 10;
    await pickBirthDate(tester, '01/01/$year');
    await tap(tester, 'Continue');
    expect(title(tester), 'Member Details');
    expect(
      find.text(
        'Under-18 registration is unavailable until guardian authorization and verification are supported.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'member-only choice skips Payment and is retained when going back',
    (tester) async {
      await pumpWizard(tester);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await tap(tester, 'Register member only');
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(
        find.text('Member-only registration · No membership or payment'),
        findsOneWidget,
      );
      await tap(tester, 'Back');
      expect(title(tester), 'Membership Plan');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tap(tester, 'Register member only');
      expect(find.textContaining('Selected plan:'), findsNothing);
      expect(continueEnabled(tester), isFalse);
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      expect(title(tester), 'Payment');
    },
  );
  testWidgets('plans load only on the plan step and selection gates Continue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final billing = FakeMembershipRepository();
    final result = await pumpWizard(tester, billing: billing);
    expect(billing.operations, isEmpty);
    await fill(tester);
    billing.planGate = Completer<BillingPage<MembershipPlan>>();
    await reveal(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loading membership plans…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
    expect(billing.operations, ['plans:$gymA:1']);
    billing.planGate!.complete(
      BillingPage([MembershipPlan.fromJson(planJson())], pagination(1, 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('₹1,500.00'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
    await tap(tester, 'Monthly');
    expect(continueEnabled(tester), isTrue);
    expect(result.members.writes, isEmpty);
    expect(billing.purchases, isEmpty);
    expect(billing.planWrites, isEmpty);
  });

  testWidgets(
    'plan failure has a safe message and Retry reloads the same scope',
    (tester) async {
      final billing = FakeMembershipRepository()
        ..failure = const BillingFailure('Plans unavailable. Please retry.');
      await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      expect(find.text('Plans unavailable. Please retry.'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
      billing.failure = null;
      await tap(tester, 'Retry');
      expect(find.text('Monthly'), findsOneWidget);
      expect(billing.operations, ['plans:$gymA:1', 'plans:$gymA:1']);
    },
  );

  testWidgets('unexpected plan exceptions are not exposed', (tester) async {
    final billing = FakeMembershipRepository()
      ..failure = StateError('private transport detail');
    await pumpWizard(tester, billing: billing);
    await fill(tester);
    await tap(tester, 'Continue');
    expect(
      find.text('Billing information could not be loaded. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets(
    'empty plans can be refreshed or skipped through member-only registration',
    (tester) async {
      final billing = FakeMembershipRepository()..empty = true;
      await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      expect(
        find.textContaining('No active membership plans.'),
        findsOneWidget,
      );
      expect(continueEnabled(tester), isFalse);
      await tap(tester, 'Refresh plans');
      expect(billing.operations.length, 2);
      await tap(tester, 'Register member only');
      expect(continueEnabled(tester), isTrue);
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(find.textContaining('Membership plan:'), findsNothing);
      expect(billing.purchases, isEmpty);
    },
  );

  testWidgets(
    'selection can change and survives member details and payment navigation',
    (tester) async {
      final quarterly = MembershipPlan.fromJson(
        planJson()..addAll({
          'id': '000000000000000000000034',
          'name': 'Quarterly',
          'durationDays': 90,
          'price': 400003,
          'description': 'Includes guided training.',
        }),
      );
      final billing = _WizardPlansRepository()
        ..pages[1] = [MembershipPlan.fromJson(planJson()), quarterly];
      await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await tap(tester, 'Quarterly');
      expect(find.text('Selected plan: Quarterly · ₹4,000.03'), findsOneWidget);
      expect(find.text('Includes guided training.'), findsOneWidget);
      expect(find.text('90 days'), findsOneWidget);
      final selected = find.byKey(ValueKey('onboarding-plan-${quarterly.id}'));
      expect(tester.widget<Material>(selected).color, AppPalette.mint);
      await tap(tester, 'Back');
      expect(value(tester, 'firstName'), 'Alex');
      await tap(tester, 'Continue');
      expect(find.text('Selected plan: Quarterly · ₹4,000.03'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(title(tester), 'Payment');
      await tap(tester, 'Back');
      expect(find.text('Selected plan: Quarterly · ₹4,000.03'), findsOneWidget);
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      expect(find.text('Membership plan: Quarterly'), findsOneWidget);
      expect(billing.purchases, isEmpty);
    },
  );

  testWidgets('free plans use the real zero price and remain selectable', (
    tester,
  ) async {
    final billing = FakeMembershipRepository()
      ..savedPlan = (planJson()..addAll({'name': 'Complimentary', 'price': 0}));
    await pumpWizard(tester, billing: billing);
    await fill(tester);
    await tap(tester, 'Continue');
    expect(find.text('Free · ₹0.00'), findsOneWidget);
    await tap(tester, 'Complimentary');
    await tap(tester, 'Continue');
    expect(
      find.text('Free plan · ₹0.00. No initial payment is required.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('initialPaymentAmount')), findsNothing);
    expect(find.text('Skip initial payment'), findsNothing);
    expect(find.text('Remaining balance: ₹0.00'), findsOneWidget);
    await tap(tester, 'Continue');
    expect(find.text('Membership plan: Complimentary'), findsOneWidget);
    expect(find.text('30 days · ₹0.00'), findsOneWidget);
    expect(billing.purchases, isEmpty);
  });

  testWidgets(
    'plan pagination preserves selection and the current page on Back',
    (tester) async {
      final later = MembershipPlan.fromJson(
        planJson()
          ..addAll({'id': '000000000000000000000034', 'name': 'Annual'}),
      );
      final billing = _WizardPlansRepository()
        ..total = 21
        ..pages[1] = [MembershipPlan.fromJson(planJson())]
        ..pages[2] = [later];
      await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await reveal(tester, find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 · 21 total'), findsOneWidget);
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      await tap(tester, 'Annual');
      await tap(tester, 'Continue');
      await tap(tester, 'Back');
      expect(find.text('Page 2 · 21 total'), findsOneWidget);
      expect(find.text('Selected plan: Annual · ₹1,500.00'), findsOneWidget);
      expect(billing.operations, contains('plans:$gymA:2'));
    },
  );

  testWidgets(
    'a pending plan result cannot render after the gym scope changes',
    (tester) async {
      final billing = FakeMembershipRepository();
      final result = await pumpWizard(
        tester,
        gyms: [gymA, gymB],
        billing: billing,
      );
      await fill(tester);
      billing.planGate = Completer<BillingPage<MembershipPlan>>();
      await reveal(tester, find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      result.scope.read(adminGymProvider.notifier).selectGym(gymB);
      billing.planGate!.complete(
        BillingPage([MembershipPlan.fromJson(planJson())], pagination(1, 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Monthly'), findsNothing);
      expect(find.textContaining('The gym context changed.'), findsOneWidget);
      expect(billing.operations, ['plans:$gymA:1']);
      billing.planGate = null;
      result.scope
          .read(appRouterProvider)
          .go('${AppRoutes.members}/new?gymId=$gymB');
      await tester.pumpAndSettle();
      expect(value(tester, 'firstName'), isEmpty);
      await fill(tester);
      await tap(tester, 'Continue');
      expect(billing.operations.last, 'plans:$gymB:1');
      expect(find.textContaining('Selected plan:'), findsNothing);
    },
  );
  testWidgets(
    'refresh preserves the choice but blocks Continue while plans are unresolved',
    (tester) async {
      final billing = FakeMembershipRepository();
      await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      billing.planGate = Completer<BillingPage<MembershipPlan>>();
      await reveal(tester, find.text('Refresh plans'));
      await tester.tap(find.text('Refresh plans'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
      billing.planGate!.completeError(
        const BillingFailure('Could not refresh plans.'),
      );
      await tester.pumpAndSettle();
      expect(continueEnabled(tester), isFalse);
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      billing.planGate = null;
      billing.empty = true;
      await tap(tester, 'Retry');
      expect(
        find.textContaining('No active membership plans.'),
        findsOneWidget,
      );
      expect(continueEnabled(tester), isFalse);
      await tap(tester, 'Register member only');
      expect(find.textContaining('Selected plan:'), findsNothing);
      expect(continueEnabled(tester), isTrue);
    },
  );

  testWidgets(
    'an account change clears the plan and loads in the new user scope',
    (tester) async {
      final billing = FakeMembershipRepository();
      final api = FakeAuthApi()..identity = adminIdentity();
      final result = await pumpWizard(tester, billing: billing, authApi: api);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      api.identity = AuthIdentity(
        user: const AuthUser(
          id: 'another-test-account',
          email: 'another@example.invalid',
          status: AccountStatus.active,
        ),
        gymAccess: adminIdentity().gymAccess,
      );
      await result.scope
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pumpAndSettle();
      expect(title(tester), 'Member Details');
      expect(value(tester, 'firstName'), isEmpty);
      await fill(tester);
      await tap(tester, 'Continue');
      expect(find.textContaining('Selected plan:'), findsNothing);
      expect(continueEnabled(tester), isFalse);
      expect(
        result.scope.read(adminGymProvider)?.userId,
        'another-test-account',
      );
      expect(
        billing.operations.where((op) => op.startsWith('plans:')).length,
        2,
      );
    },
  );

  Future<void> enterPayment(WidgetTester tester, String amount) async {
    await reveal(tester, find.byKey(const ValueKey('initialPaymentAmount')));
    await tester.enterText(
      find.byKey(const ValueKey('initialPaymentAmount')),
      amount,
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseMethod(WidgetTester tester, PaymentMethod method) async {
    await reveal(tester, find.byKey(const ValueKey('initialPaymentMethod')));
    await tester.tap(find.byKey(const ValueKey('initialPaymentMethod')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(method.label).last);
    await tester.pumpAndSettle();
  }

  Future<void> openPayment(
    WidgetTester tester, {
    FakeMembershipRepository? billing,
  }) async {
    await pumpWizard(tester, billing: billing);
    await fill(tester);
    await tap(tester, 'Continue');
    await tap(tester, 'Monthly');
    await tap(tester, 'Continue');
  }

  testWidgets(
    'optional initial payment shows full remaining balance and records nothing',
    (tester) async {
      final billing = FakeMembershipRepository();
      await openPayment(tester, billing: billing);
      expect(find.text('Skip initial payment'), findsOneWidget);
      expect(find.byKey(const ValueKey('initialPaymentAmount')), findsNothing);
      expect(find.text('Plan price: ₹1,500.00'), findsOneWidget);
      expect(find.text('Initial payment: ₹0.00'), findsOneWidget);
      expect(find.text('Remaining balance: ₹1,500.00'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(find.text('Payment method: Cash'), findsNothing);
      expect(billing.purchases, isEmpty);
      expect(billing.planWrites, isEmpty);
    },
  );

  testWidgets(
    'cash partial payment previews exact balance and survives Back and Continue',
    (tester) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '500.03');
      expect(find.text('Remaining balance: ₹999.97'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(find.text('Initial payment: ₹500.03'), findsOneWidget);
      expect(find.text('Payment method: Cash'), findsOneWidget);
      await tap(tester, 'Back');
      expect(value(tester, 'initialPaymentAmount'), '500.03');
      await tap(tester, 'Back');
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(value(tester, 'initialPaymentAmount'), '500.03');
      expect(value(tester, 'initialPaymentReference'), isEmpty);
    },
  );

  for (final input in ['-1', '1.234', '1500.01']) {
    testWidgets('invalid payment $input prevents advancing to review', (
      tester,
    ) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, input);
      await tap(tester, 'Continue');
      expect(title(tester), 'Payment');
      expect(
        find.text(
          input == '1500.01'
              ? 'Initial payment cannot exceed the plan price.'
              : 'Enter rupees with at most two decimal places.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Remaining balance: Enter a valid amount'),
        findsOneWidget,
      );
    });
  }

  for (final method in [
    PaymentMethod.upi,
    PaymentMethod.bankTransfer,
    PaymentMethod.card,
  ]) {
    testWidgets(
      '${method.label} requires a reference and preserves it in the local draft',
      (tester) async {
        await openPayment(tester);
        await tap(tester, 'Skip initial payment');
        await enterPayment(tester, '100');
        await chooseMethod(tester, method);
        await tap(tester, 'Continue');
        expect(title(tester), 'Payment');
        expect(find.text('A payment reference is required.'), findsOneWidget);
        await reveal(
          tester,
          find.byKey(const ValueKey('initialPaymentReference')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('initialPaymentReference')),
          ' REF-123 ',
        );
        await tester.pumpAndSettle();
        await tap(tester, 'Continue');
        expect(title(tester), 'Review & Confirm');
        expect(find.text('Reference: REF-123'), findsOneWidget);
        expect(find.text('Payment method: ${method.label}'), findsOneWidget);
        await tap(tester, 'Back');
        expect(value(tester, 'initialPaymentReference'), ' REF-123 ');
        expect(
          tester
              .widget<DropdownButtonFormField<PaymentMethod>>(
                find.byKey(const ValueKey('initialPaymentMethod')),
              )
              .initialValue,
          method,
        );
      },
    );
  }

  testWidgets(
    'zero initial payment does not require a digital payment reference',
    (tester) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '0.00');
      await chooseMethod(tester, PaymentMethod.upi);
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(find.text('Initial payment: ₹0.00'), findsOneWidget);
      expect(find.text('Remaining balance: ₹1,500.00'), findsOneWidget);
      expect(find.text('Payment method: UPI'), findsNothing);
    },
  );

  testWidgets(
    'explicitly skipping clears amount, method and reference instead of restoring stale data',
    (tester) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '100');
      await chooseMethod(tester, PaymentMethod.upi);
      await reveal(
        tester,
        find.byKey(const ValueKey('initialPaymentReference')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('initialPaymentReference')),
        'UPI-123',
      );
      await tap(tester, 'Skip initial payment');
      expect(find.byKey(const ValueKey('initialPaymentAmount')), findsNothing);
      await tap(tester, 'Continue');
      expect(find.text('Initial payment: ₹0.00'), findsOneWidget);
      expect(find.text('Reference: UPI-123'), findsNothing);
      await tap(tester, 'Back');
      await tap(tester, 'Skip initial payment');
      expect(value(tester, 'initialPaymentAmount'), isEmpty);
      expect(value(tester, 'initialPaymentReference'), isEmpty);
      expect(
        tester
            .widget<DropdownButtonFormField<PaymentMethod>>(
              find.byKey(const ValueKey('initialPaymentMethod')),
            )
            .initialValue,
        PaymentMethod.cash,
      );
    },
  );

  testWidgets(
    'register member only clears the existing plan and payment together',
    (tester) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '100');
      await tap(tester, 'Back');
      await tap(tester, 'Register member only');
      await tap(tester, 'Continue');
      expect(title(tester), 'Review & Confirm');
      expect(find.text('Plan price: ₹1,500.00'), findsNothing);
      expect(find.text('Initial payment: ₹100.00'), findsNothing);
      await tap(tester, 'Back');
      await tap(tester, 'Register member only');
      expect(find.textContaining('Selected plan:'), findsNothing);
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      expect(find.byKey(const ValueKey('initialPaymentAmount')), findsNothing);
      await tap(tester, 'Skip initial payment');
      expect(value(tester, 'initialPaymentAmount'), isEmpty);
    },
  );

  testWidgets(
    'payment editing works independently of plan loading or invalidation',
    (tester) async {
      final billing = FakeMembershipRepository();
      final result = await pumpWizard(tester, billing: billing);
      await fill(tester);
      await tap(tester, 'Continue');
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      billing.planGate = Completer<BillingPage<MembershipPlan>>();
      result.scope.invalidate(activePlansProvider);
      await tester.pump();
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '1500');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tap(tester, 'Continue');
      expect(find.text('Remaining balance: ₹0.00'), findsOneWidget);
      expect(billing.operations, ['plans:$gymA:1']);
      expect(billing.purchases, isEmpty);
      expect(result.members.writes, isEmpty);
    },
  );

  for (final path in [
    'member only',
    'membership only',
    'membership and payment',
  ]) {
    testWidgets(
      '$path review enables confirmation without separate member or purchase writes',
      (tester) async {
        final billing = FakeMembershipRepository();
        final result = await pumpWizard(tester, billing: billing);
        await fill(tester);
        await tap(tester, 'Continue');
        if (path == 'member only') {
          await tap(tester, 'Register member only');
          await tap(tester, 'Continue');
          expect(find.text('Member registration only'), findsOneWidget);
        } else {
          await tap(tester, 'Monthly');
          await tap(tester, 'Continue');
          if (path == 'membership and payment') {
            await tap(tester, 'Skip initial payment');
            await enterPayment(tester, '500.03');
          }
          await tap(tester, 'Continue');
          expect(
            find.text(
              path == 'membership only'
                  ? 'Member + membership'
                  : 'Member + membership + initial payment',
            ),
            findsOneWidget,
          );
        }
        expect(title(tester), 'Review & Confirm');
        expect(find.text(onboardingConfirmationMessage), findsOneWidget);
        await reveal(tester, find.text('Confirm registration'));
        expect(
          tester
              .widget<FilledButton>(
                find.ancestor(
                  of: find.text('Confirm registration'),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is FilledButton,
                  ),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(title(tester), 'Review & Confirm');
        expect(result.members.writes, isEmpty);
        expect(billing.purchases, isEmpty);
        expect(billing.planWrites, isEmpty);
      },
    );
  }

  testWidgets(
    'review edit shortcuts correct member details without losing the plan or payment',
    (tester) async {
      await openPayment(tester);
      await tap(tester, 'Skip initial payment');
      await enterPayment(tester, '500.03');
      await chooseMethod(tester, PaymentMethod.bankTransfer);
      await reveal(
        tester,
        find.byKey(const ValueKey('initialPaymentReference')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('initialPaymentReference')),
        ' BANK-123 ',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Continue');
      await tap(tester, 'Edit member details');
      expect(title(tester), 'Member Details');
      expect(value(tester, 'dateOfBirth'), 'Jan 2, 2000');
      await reveal(tester, find.byKey(const ValueKey('firstName')));
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        ' Updated ',
      );
      await tap(tester, 'Continue');
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(value(tester, 'initialPaymentAmount'), '500.03');
      expect(value(tester, 'initialPaymentReference'), ' BANK-123 ');
      await tap(tester, 'Continue');
      expect(find.text('Updated River'), findsOneWidget);
      expect(find.text('Reference: BANK-123'), findsOneWidget);
      await tap(tester, 'Edit initial payment');
      expect(title(tester), 'Payment');
      expect(value(tester, 'initialPaymentAmount'), '500.03');
      await tap(tester, 'Continue');
      await tap(tester, 'Edit membership selection');
      expect(title(tester), 'Membership Plan');
      expect(find.text('Selected plan: Monthly · ₹1,500.00'), findsOneWidget);
    },
  );

  testWidgets(
    'gym mismatch blocks the local draft and switching back resets it',
    (tester) async {
      final result = await pumpWizard(tester, gyms: [gymA, gymB]);
      await fill(tester);
      result.scope.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingProgress), findsNothing);
      expect(
        find.text('The gym context changed. Return to Members to continue.'),
        findsOneWidget,
      );
      result.scope.read(adminGymProvider.notifier).selectGym(gymA);
      await tester.pumpAndSettle();
      expect(value(tester, 'firstName'), isEmpty);
      expect(result.members.writes, isEmpty);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness wizard supports double text scaling through review',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        const name = 'Complete fitness and personal training membership';
        final billing = FakeMembershipRepository()
          ..savedPlan = (planJson()
            ..addAll({
              'name': name,
              'price': maximumPaymentPaise,
              'description':
                  'A detailed membership description that should wrap comfortably on a small phone.',
            }));
        await pumpWizard(tester, billing: billing);
        await fill(tester);
        await tap(tester, 'Continue');
        await tap(tester, name);
        await tap(tester, 'Continue');
        await tap(tester, 'Skip initial payment');
        await enterPayment(tester, '500.03');
        await chooseMethod(tester, PaymentMethod.bankTransfer);
        await reveal(
          tester,
          find.byKey(const ValueKey('initialPaymentReference')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('initialPaymentReference')),
          'BANK-123',
        );
        await tester.pumpAndSettle();
        await tap(tester, 'Continue');
        await reveal(tester, find.text('Confirm registration'));
        expect(title(tester), 'Review & Confirm');
        expect(find.text('Initial payment: ₹500.03'), findsOneWidget);
        expect(find.text('Payment method: Bank transfer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _WizardPlansRepository extends FakeMembershipRepository {
  final pages = <int, List<MembershipPlan>>{};
  @override
  Future<BillingPage<MembershipPlan>> plans(String gymId, int page) async {
    final fallback = await super.plans(gymId, page);
    return pages.containsKey(page)
        ? BillingPage(pages[page]!, pagination(page, total))
        : fallback;
  }
}
