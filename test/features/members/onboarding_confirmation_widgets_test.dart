import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import '../memberships/billing_fakes.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart';

class PilotConfig extends Notifier<AppConfig> {
  @override
  AppConfig build() => AppConfig.fromValues(apiBaseUrl: onboardingUrl);
  void change(String url) => state = AppConfig.fromValues(apiBaseUrl: url);
}

final pilotConfigProvider = NotifierProvider<PilotConfig, AppConfig>(
  PilotConfig.new,
);

class ConfirmationStorage extends TestOnboardingStorage {
  final attemptedValues = <String>[];
  int? failOnWriteNumber;
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) {
    if (value != null) attemptedValues.add(value);
    if (attemptedValues.length == failOnWriteNumber) {
      return Future.error(StateError('Synthetic selected write failure'));
    }
    return super.write(key: key, value: value);
  }
}

class ConfirmationRepository extends FakeOnboardingRepository {
  int price = 150000;
  @override
  Future<OnboardingResult> complete(
    String gymId,
    OnboardingRequest request,
    String idempotencyKey, {
    CancelToken? cancelToken,
  }) async {
    final result = await super.complete(
      gymId,
      request,
      idempotencyKey,
      cancelToken: cancelToken,
    );
    if (price == 150000) return result;
    return OnboardingResult.fromJson(
      onboardingResultJson(request, gymId: gymId, price: price),
    );
  }
}

void main() {
  late ProviderContainer container;
  late ConfirmationStorage storage;
  late ConfirmationRepository repository;
  late FakeMemberRepository members;
  late FakeMembershipRepository billing;
  late FakeAuthApi auth;
  setUp(() {
    storage = ConfirmationStorage();
    repository = ConfirmationRepository();
    members = FakeMemberRepository();
    billing = FakeMembershipRepository();
    auth = FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]);
  });
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => ref.watch(pilotConfigProvider)),
        authApiServiceProvider.overrideWithValue(auth),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()..value = syntheticCredential(),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(members),
        membershipRepositoryProvider.overrideWithValue(billing),
        memberOnboardingRepositoryProvider.overrideWithValue(repository),
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        pendingOnboardingStoreProvider.overrideWithValue(
          SecurePendingOnboardingStore(
            storage: storage,
            queue: OnboardingOperationQueue(),
          ),
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
        .go('${AppRoutes.members}/new?gymId=$gymA');
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await reveal(tester, find.text(label));
    await tester.tap(find.text(label));
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

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await reveal(tester, field);
    await tester.enterText(field, value);
  }

  Future<void> review(
    WidgetTester tester, {
    bool memberOnly = false,
    String? amount,
    String? reference,
  }) async {
    for (final entry in {
      'firstName': 'Alex',
      'lastName': 'River',
      'phone': '9876543210',
    }.entries) {
      await enter(tester, entry.key, entry.value);
    }
    await pickBirthDate(tester, '01/02/2000');
    await tap(tester, 'Continue');
    if (memberOnly) {
      await tap(tester, 'Register member only');
      await tap(tester, 'Continue');
    } else {
      await tap(tester, 'Monthly');
      await tap(tester, 'Continue');
      if (amount != null) {
        await tap(tester, 'Skip initial payment');
        await enter(tester, 'initialPaymentAmount', amount);
        if (reference != null) {
          await reveal(tester, find.byKey(const Key('initialPaymentMethod')));
          await tester.tap(find.text('Cash'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('UPI').last);
          await tester.pumpAndSettle();
          await enter(tester, 'initialPaymentReference', reference);
        }
      }
      await tap(tester, 'Continue');
    }
    if (find.text('Confirm registration').evaluate().isNotEmpty) {
      await reveal(tester, find.text('Confirm registration'));
    }
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Confirm registration'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );
  PendingOnboardingOperation saved() => PendingOnboardingOperation.decode(
    storage.values[onboardingScope().storageKey]!,
  );
  Map<String, dynamic> body() =>
      jsonDecode(repository.calls.single.body) as Map<String, dynamic>;

  testWidgets(
    'active registration blocks tabs, drawer, gym change and system Back',
    (tester) async {
      await mount(tester);
      await review(tester, memberOnly: true);
      repository.gate = Completer<OnboardingResult>();
      confirm(tester).onPressed!();
      // Exercise exit before the busy screen's first rebuild as well.
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected!(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.calls, hasLength(1));
      expect(find.text('Discard unsaved changes?'), findsNothing);
      final key = saved().idempotencyKey;
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected!(0);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.byTooltip('Admin navigation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Dashboard'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Gym $gymB').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(adminGymProvider)!.gymId, gymA);
      expect(find.text('Discard unsaved changes?'), findsNothing);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '${AppRoutes.members}/new',
      );
      expect(saved().idempotencyKey, key);
      expect(repository.calls, hasLength(1));
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(saved().request)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(saved().idempotencyKey, key);
    },
  );

  for (final path in [
    'member only',
    'membership only',
    'membership/payment',
    'zero payment',
    'free plan',
  ]) {
    testWidgets(
      '$path confirmation performs one atomic request with exact field mapping',
      (tester) async {
        if (path == 'free plan') {
          billing.savedPlan = {...planJson(), 'price': 0};
          repository.price = 0;
        }
        await mount(tester);
        await review(
          tester,
          memberOnly: path == 'member only',
          amount: path == 'membership/payment'
              ? '500.03'
              : path == 'zero payment'
              ? '0'
              : null,
          reference: path == 'membership/payment' ? ' REF-123 ' : null,
        );
        expect(confirm(tester).onPressed, isNotNull);
        expect(repository.calls, isEmpty);
        await tap(tester, 'Confirm registration');
        expect(repository.calls, hasLength(1));
        // No code: the server numbers the member.
        expect(body()['member'], {
          'firstName': 'Alex',
          'lastName': 'River',
          'phone': '9876543210',
          'dateOfBirth': '2000-01-02',
        });
        if (path == 'member only') {
          expect(body().containsKey('membership'), isFalse);
        } else {
          final membership = body()['membership'] as Map;
          expect(membership['planId'], planId);
          expect(membership.containsKey('startDate'), isFalse);
          if (path == 'membership/payment') {
            final payment = membership['payment'] as Map;
            expect(payment['amountPaise'], 50003);
            expect(payment['method'], 'upi');
            expect(payment['reference'], 'REF-123');
            final paidAt = DateTime.parse(payment['paidAt'] as String);
            expect(paidAt.isUtc, isTrue);
            expect(paidAt.microsecond, 0);
            expect(find.text('Outstanding balance: ₹999.97'), findsOneWidget);
          } else {
            expect(membership.containsKey('payment'), isFalse);
          }
        }
        expect(saved().version, 2);
        expect(saved().result, isNotNull);
        expect(saved().idempotencyKey, repository.calls.single.key);
        expect(saved().request.frozenJson, repository.calls.single.body);
        expect(find.text('Registration confirmed'), findsOneWidget);
        expect(find.text('Alex River'), findsOneWidget);
        if (path == 'free plan') {
          expect(find.text('Plan price: ₹0.00'), findsOneWidget);
          expect(find.text('Outstanding balance: ₹0.00'), findsOneWidget);
        }
        expect(members.writes, isEmpty);
        expect(billing.purchases, isEmpty);
        final encoded = saved().encode();
        await tap(tester, 'View member details');
        expect(
          container.read(appRouterProvider).state.uri.path,
          '${AppRoutes.members}/${saved().result!.member.id}',
        );
        expect(storage.values[onboardingScope().storageKey], encoded);
        container.read(appRouterProvider).pop();
        await tester.pumpAndSettle();
        await tap(tester, 'Done, add next member');
        expect(storage.values, isEmpty);
        expect(find.byKey(const ValueKey('firstName')), findsOneWidget);
        expect(repository.calls, hasLength(1));
      },
    );
  }

  testWidgets(
    'invalid member and overpayment are stopped before atomic submission',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Continue');
      expect(repository.calls, isEmpty);
      expect(storage.values, isEmpty);
      await review(tester, amount: '1500.01');
      expect(find.byKey(const Key('onboarding-step-title')), findsOneWidget);
      expect(
        find.text('Initial payment cannot exceed the plan price.'),
        findsWidgets,
      );
      expect(find.text('Confirm registration'), findsNothing);
      expect(repository.calls, isEmpty);
      expect(storage.values, isEmpty);
    },
  );
  testWidgets('an old Confirm callback cannot submit a draft being corrected', (
    tester,
  ) async {
    await mount(tester);
    await review(tester, memberOnly: true);
    final callback = confirm(tester).onPressed!;
    await tap(tester, 'Edit member details');
    await enter(tester, 'phone', '123');
    callback();
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(storage.values, isEmpty);
    await tap(tester, 'Continue');
    expect(find.text('Enter a phone number with 7–15 digits.'), findsOneWidget);
    expect(find.byKey(const ValueKey('firstName')), findsOneWidget);
  });
  testWidgets(
    'invalid selected plan disables final Confirm and explains correction',
    (tester) async {
      billing.savedPlan = {...planJson(), 'status': 'inactive'};
      await mount(tester);
      await review(tester);
      expect(confirm(tester).onPressed, isNull);
      expect(
        find.text('Choose an active membership plan for the current gym.'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
      expect(storage.values, isEmpty);
      await tap(tester, 'Fix Membership Plan');
      expect(find.byKey(const Key('onboarding-step-title')), findsOneWidget);
    },
  );
  testWidgets('unresolved recovery never exposes a fresh Confirm action', (
    tester,
  ) async {
    final operation = preparedOperation();
    storage.values[operation.scope.storageKey] = operation.encode();
    storage.readGate = Completer<void>();
    await mount(tester, settle: false);
    expect(find.text('Confirm registration'), findsNothing);
    expect(find.byKey(const ValueKey('firstName')), findsNothing);
    storage.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Retry saved registration'), findsOneWidget);
    expect(find.text('Confirm registration'), findsNothing);
    expect(repository.calls, isEmpty);
  });
  testWidgets(
    'double Confirm callbacks and taps cannot freeze or send two operations',
    (tester) async {
      repository.gate = Completer<OnboardingResult>();
      await mount(tester);
      await review(tester, memberOnly: true);
      final callback = confirm(tester).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(find.text('Confirm registration'), findsNothing);
      expect(saved().attempts, hasLength(1));
      final request = OnboardingRequest.fromFrozenJson(
        repository.calls.single.body,
      );
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(request)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsOneWidget);
      final keys = storage.attemptedValues
          .map(PendingOnboardingOperation.decode)
          .map((op) => op.idempotencyKey)
          .toSet();
      expect(keys, {repository.calls.single.key});
    },
  );
  testWidgets(
    'network failure preserves key/body/timestamp; retry confirms the same operation',
    (tester) async {
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await mount(tester);
      await review(tester, amount: '500.03');
      await tap(tester, 'Confirm registration');
      expect(saved().status, PendingOnboardingStatus.uncertain);
      expect(find.text('Confirm registration'), findsNothing);
      final original = saved();
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls, hasLength(2));
      expect(repository.calls.map((call) => call.key).toSet(), {
        original.idempotencyKey,
      });
      expect(repository.calls.map((call) => call.body).toSet(), {
        original.request.frozenJson,
      });
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(saved().attempts.map((a) => a.outcome), [
        OnboardingAttemptOutcome.unresolved,
        OnboardingAttemptOutcome.confirmed,
      ]);
    },
  );
  for (final code in [
    OnboardingBackendCode.idempotencyKeyConflict,
    OnboardingBackendCode.duplicateMemberCode,
    OnboardingBackendCode.planNotFound,
  ]) {
    testWidgets(
      '${code.wireValue} retains durable evidence and blocks fresh confirmation',
      (tester) async {
        repository.failure = OnboardingFailure(
          code.kind,
          backendRejection: OnboardingBackendRejection.tryFrom(
            code.wireValue,
            code.status,
          ),
        );
        await mount(tester);
        await review(tester, memberOnly: true);
        await tap(tester, 'Confirm registration');
        expect(saved().attempts.single.rejection!.code, code);
        expect(
          saved().status,
          code == OnboardingBackendCode.idempotencyKeyConflict
              ? PendingOnboardingStatus.reconciliationRequired
              : PendingOnboardingStatus.rejected,
        );
        expect(find.text('Confirm registration'), findsNothing);
        expect(find.text('Retry saved registration'), findsNothing);
        final encoded = saved().encode();
        await tap(tester, 'Recheck saved registration');
        expect(saved().encode(), encoded);
        expect(repository.calls, hasLength(1));
      },
    );
  }
  testWidgets(
    'unexpected repository error is safe, retained, and recoverable',
    (tester) async {
      repository.failure = StateError('raw-sensitive-internal-detail');
      await mount(tester);
      await review(tester, memberOnly: true);
      await tap(tester, 'Confirm registration');
      expect(saved().status, PendingOnboardingStatus.uncertain);
      expect(find.textContaining('raw-sensitive'), findsNothing);
      expect(find.text('Retry saved registration'), findsOneWidget);
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );
  testWidgets(
    'initial save failure never sends; recheck cannot create a new key; retry saves the exact preparation',
    (tester) async {
      await mount(tester);
      await review(tester, amount: '500.03');
      storage.failWrite = true;
      await tap(tester, 'Confirm registration');
      expect(repository.calls, isEmpty);
      expect(storage.values, isEmpty);
      final original = PendingOnboardingOperation.decode(
        storage.attemptedValues.single,
      );
      await tap(tester, 'Recheck saved registration');
      expect(find.text('Confirm registration'), findsNothing);
      storage.failWrite = false;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls.single.key, original.idempotencyKey);
      expect(repository.calls.single.body, original.request.frozenJson);
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );
  testWidgets('prepared persistence completes before any POST', (tester) async {
    await mount(tester);
    await review(tester, memberOnly: true);
    storage.writeGate = Completer<void>();
    storage.writeEntered = Completer<void>();
    confirm(tester).onPressed!();
    await tester.pump();
    expect(storage.writes, 1);
    expect(repository.calls, isEmpty);
    // Only releasing the prepared save allows dispatch to advance.
    final first = storage.writeGate!;
    storage.writeGate = null;
    first.complete();
    await tester.pump();
    // The service must still save/verify a marker after this prepared save.
    await tester.pumpAndSettle();
    expect(find.text('Registration confirmed'), findsOneWidget);
  });
  testWidgets(
    'failed dispatch-marker write prevents POST and preserves the prepared request',
    (tester) async {
      await mount(tester);
      await review(tester, memberOnly: true);
      storage.failOnWriteNumber = 2;
      await tap(tester, 'Confirm registration');
      expect(repository.calls, isEmpty);
      expect(saved().status, PendingOnboardingStatus.prepared);
      final original = saved();
      await tap(tester, 'Retry saved registration');
      expect(repository.calls.single.key, original.idempotencyKey);
      expect(repository.calls.single.body, original.request.frozenJson);
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );
  testWidgets(
    'failed confirmation persistence never shows success and exact retry recovers',
    (tester) async {
      repository.gate = Completer<OnboardingResult>();
      await mount(tester);
      await review(tester, memberOnly: true);
      confirm(tester).onPressed!();
      await tester.pump();
      final original = saved();
      storage.failWrite = true;
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(original.request)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsNothing);
      expect(saved().result, isNull);
      storage.failWrite = false;
      repository.gate = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls.map((call) => call.key).toSet(), {
        original.idempotencyKey,
      });
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );
  testWidgets(
    'another pending operation appearing after gate check cannot be overwritten or dispatched as fresh',
    (tester) async {
      await mount(tester);
      await review(tester, memberOnly: true);
      final other = preparedOperation();
      storage.values[other.scope.storageKey] = other.encode();
      await tap(tester, 'Confirm registration');
      expect(repository.calls, isEmpty);
      expect(saved().encode(), other.encode());
      expect(find.text('Confirm registration'), findsNothing);
    },
  );
  testWidgets(
    'stale Confirm and acknowledgement callbacks are inert after a gym change',
    (tester) async {
      await mount(tester);
      await review(tester, memberOnly: true);
      final callback = confirm(tester).onPressed!;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      callback();
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      expect(storage.values, isEmpty);
      container.read(adminGymProvider.notifier).selectGym(gymA);
      await tester.pumpAndSettle();
      await review(tester, memberOnly: true);
      await tap(tester, 'Confirm registration');
      final original = saved().encode();
      final acknowledge = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Done, add next member'),
          )
          .onPressed!;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      acknowledge();
      await tester.pumpAndSettle();
      expect(storage.values[onboardingScope().storageKey], original);
      expect(repository.calls, hasLength(1));
    },
  );
  for (final change in ['gym', 'account', 'API']) {
    testWidgets(
      '$change change during submission retains original operation without stale success/navigation',
      (tester) async {
        repository.gate = Completer<OnboardingResult>();
        await mount(tester);
        await review(tester, memberOnly: true);
        confirm(tester).onPressed!();
        await tester.pump();
        final original = saved();
        final oldLocation = container.read(appRouterProvider).state.uri.path;
        if (change == 'gym') {
          container.read(adminGymProvider.notifier).selectGym(gymB);
        }
        if (change == 'API') {
          container
              .read(pilotConfigProvider.notifier)
              .change('https://other.example.invalid/api/v1/');
        }
        if (change == 'account') {
          await container.read(sessionControllerProvider.notifier).logout();
          auth.identity = AuthIdentity(
            user: const AuthUser(
              id: 'other-account',
              email: 'other@example.invalid',
              status: AccountStatus.active,
            ),
            gymAccess: adminIdentity().gymAccess,
          );
          await container
              .read(sessionControllerProvider.notifier)
              .login(
                email: 'other@example.invalid',
                password: syntheticCredential(),
              );
          container
              .read(appRouterProvider)
              .go('${AppRoutes.members}/new?gymId=$gymA');
        }
        await tester.pump();
        expect(repository.calls.single.cancel!.isCancelled, isTrue);
        repository.gate!.complete(
          OnboardingResult.fromJson(onboardingResultJson(original.request)),
        );
        await tester.pumpAndSettle();
        expect(saved().status, PendingOnboardingStatus.uncertain);
        expect(saved().idempotencyKey, original.idempotencyKey);
        expect(find.text('Registration confirmed'), findsNothing);
        expect(repository.calls, hasLength(1));
        expect(container.read(appRouterProvider).state.uri.path, oldLocation);
        expect(storage.values, hasLength(1));
      },
    );
  }
}
