import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_repository.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import '../memberships/billing_fakes.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/members/providers/member_overview_providers.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart';

class CountingRecoveryStorage extends TestOnboardingStorage {
  int reads = 0;
  final writtenOperations = <PendingOnboardingOperation>[];
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
    if (value != null) {
      writtenOperations.add(PendingOnboardingOperation.decode(value));
    }
    return super.write(key: key, value: value);
  }

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) {
    reads++;
    return super.read(key: key);
  }
}

void main() {
  late CountingRecoveryStorage storage;
  late FakeOnboardingRepository repository;
  late FakeAuthApi auth;
  late ProviderContainer container;
  late FakeDashboardRepository dashboardRepository;
  late FakeMembershipRepository billingRepository;
  late FakeMemberRepository membersRepository;

  setUp(() {
    storage = CountingRecoveryStorage();
    repository = FakeOnboardingRepository();
    auth = FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]);
    dashboardRepository = FakeDashboardRepository();
    billingRepository = FakeMembershipRepository();
    membersRepository = FakeMemberRepository();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool settle = true,
    String url = onboardingUrl,
    MemberOnboardingRepository? recoveryRepository,
  }) async {
    container = ProviderContainer(
      overrides: [
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: url),
        ),
        authApiServiceProvider.overrideWithValue(auth),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()..value = syntheticCredential(),
        ),
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
        memberRepositoryProvider.overrideWithValue(membersRepository),
        // The members list sits under the onboarding page; keep its reads
        // off the network like every other repository here.
        memberOverviewRepositoryProvider.overrideWithValue(
          FakeMemberOverviewRepository(membersRepository),
        ),
        membershipRepositoryProvider.overrideWithValue(billingRepository),
        memberOnboardingRepositoryProvider.overrideWithValue(
          recoveryRepository ?? repository,
        ),
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

  void save(PendingOnboardingOperation operation) =>
      storage.values[operation.scope.storageKey] = operation.encode();
  PendingOnboardingOperation confirmed({
    bool legacy = false,
    bool membership = false,
    int? amount,
  }) {
    final operation = legacy
        ? pendingOperation(
            request: onboardingRequest(membership: membership, amount: amount),
          )
        : preparedOperation(
            request: onboardingRequest(membership: membership, amount: amount),
          );
    final result = OnboardingResult.fromJson(
      onboardingResultJson(operation.request),
    );
    return legacy
        ? operation.confirmed(result)
        : operation.withLedger(
            revision: 2,
            attempts: [
              OnboardingAttempt(
                number: 1,
                dispatchedAt: DateTime.utc(2026),
                outcome: OnboardingAttemptOutcome.confirmed,
              ),
            ],
            result: result,
          );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final target = find.text(label);
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder getForm() => find.byKey(const ValueKey('memberCode'));

  testWidgets(
    'confirmed onboarding refreshes current gym revenue and outstanding dues',
    (tester) async {
      save(
        preparedOperation(
          request: onboardingRequest(membership: true, amount: 100000),
        ),
      );
      dashboardRepository.result = GymDashboard.fromJson(
        dashboardJson(revenue: 0, outstanding: 0),
      );
      await mount(tester);
      container.listen(dashboardProvider, (_, _) {});
      await container.read(dashboardProvider.future);
      final before = dashboardRepository.requests.length;
      dashboardRepository.result = GymDashboard.fromJson(
        dashboardJson(revenue: 100000, outstanding: 50000),
      );
      await tap(tester, 'Retry saved registration');
      final refreshed = (await container.read(dashboardProvider.future))!;
      expect(refreshed.payments.periodSuccessfulAmountPaise, 100000);
      expect(refreshed.payments.outstandingAmountPaise, 50000);
      expect(dashboardRepository.requests.length, before + 1);
      expect(dashboardRepository.requests.last.gymId, gymA);
      expect(repository.calls, hasLength(1));
    },
  );

  testWidgets(
    'empty storage is verified once before showing a local draft; no POST',
    (tester) async {
      await mount(tester);
      expect(getForm(), findsOneWidget);
      expect(storage.reads, 1);
      expect(storage.writes, 0);
      expect(repository.calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Retained',
      );
      container.read(dashboardQueryProvider.notifier).useGymToday();
      await tester.pumpAndSettle();
      expect(storage.reads, 1);
      expect(find.text('Retained'), findsOneWidget);
    },
  );

  testWidgets('pending restore blocks fresh form until secure read completes', (
    tester,
  ) async {
    save(preparedOperation());
    storage.readGate = Completer<void>();
    await mount(tester, settle: false);
    expect(
      find.text('Checking saved registration. Please wait.'),
      findsOneWidget,
    );
    expect(getForm(), findsNothing);
    expect(repository.calls, isEmpty);
    storage.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Retry saved registration'), findsOneWidget);
    expect(getForm(), findsNothing);
    expect(storage.writes, 0);
  });

  for (final legacy in [false, true]) {
    testWidgets(
      'exact retry uses frozen request/key and confirms durably (${legacy ? 'v1' : 'v2'})',
      (tester) async {
        final operation = legacy
            ? pendingOperation(
                request: onboardingRequest(membership: true, amount: 50003),
              )
            : preparedOperation(
                request: onboardingRequest(membership: true, amount: 50003),
              );
        save(operation);
        await mount(tester);
        expect(repository.calls, isEmpty);
        await tap(tester, 'Retry saved registration');
        expect(repository.calls, hasLength(1));
        expect(repository.calls.single.body, operation.request.frozenJson);
        expect(repository.calls.single.key, operation.idempotencyKey);
        final saved = PendingOnboardingOperation.decode(
          storage.values[operation.scope.storageKey]!,
        );
        expect(saved.version, legacy ? 1 : 2);
        expect(saved.result, isNotNull);
        expect(saved.request.frozenJson, operation.request.frozenJson);
        expect(saved.idempotencyKey, operation.idempotencyKey);
        expect(find.text('Registration confirmed'), findsOneWidget);
        expect(find.text('Amount received: ₹500.03'), findsOneWidget);
        expect(find.text('Outstanding balance: ₹999.97'), findsOneWidget);
        expect(getForm(), findsNothing);
      },
    );

    testWidgets(
      'restored confirmation is not resubmitted; explicit acknowledgement unlocks (${legacy ? 'v1' : 'v2'})',
      (tester) async {
        final operation = confirmed(legacy: legacy);
        save(operation);
        await mount(tester);
        expect(find.text('Registration confirmed'), findsOneWidget);
        expect(find.text('Alex River'), findsOneWidget);
        expect(repository.calls, isEmpty);
        expect(storage.values[operation.scope.storageKey], operation.encode());
        await tap(tester, 'Acknowledge registration');
        expect(storage.values, isEmpty);
        expect(getForm(), findsOneWidget);
        expect(repository.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'network retry remains blocked and next retry reuses the same submission',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      expect(getForm(), findsNothing);
      expect(find.textContaining('The outcome is uncertain.'), findsOneWidget);
      expect(
        PendingOnboardingOperation.decode(
          storage.values[operation.scope.storageKey]!,
        ).status,
        PendingOnboardingStatus.uncertain,
      );
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls, hasLength(2));
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(repository.calls.map((call) => call.body).toSet(), {
        operation.request.frozenJson,
      });
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  for (final code in [
    OnboardingBackendCode.idempotencyKeyConflict,
    OnboardingBackendCode.duplicateMemberCode,
  ]) {
    testWidgets(
      '${code.wireValue} blocks a fresh draft and offers only the supported recovery action',
      (tester) async {
        final operation = preparedOperation();
        final evidence = OnboardingBackendRejection.tryFrom(
          code.wireValue,
          code.status,
        )!;
        final blocked = operation.withLedger(
          revision: 2,
          attempts: [
            OnboardingAttempt(
              number: 1,
              dispatchedAt: DateTime.utc(2026),
              outcome: code == OnboardingBackendCode.idempotencyKeyConflict
                  ? OnboardingAttemptOutcome.conflict
                  : OnboardingAttemptOutcome.rejected,
              rejection: evidence,
            ),
          ],
        );
        save(blocked);
        await mount(tester);
        expect(getForm(), findsNothing);
        expect(find.text('Retry saved registration'), findsNothing);
        expect(find.text('Recheck saved registration'), findsOneWidget);
        expect(
          find.textContaining(
            code == OnboardingBackendCode.idempotencyKeyConflict
                ? 'We cannot yet verify whether this registration was completed'
                : 'This registration was not completed',
          ),
          findsOneWidget,
        );
        await tap(tester, 'Recheck saved registration');
        expect(find.byKey(const ValueKey('recoveryFeedback')), findsOneWidget);
        expect(
          find.textContaining('Latest recheck:', skipOffstage: false),
          findsWidgets,
        );
        expect(find.textContaining('No request was sent.'), findsWidgets);
        expect(
          find.text('Saved rejection: HTTP 409 · ${code.wireValue}'),
          findsOneWidget,
        );
        expect(find.text('Return to Members'), findsOneWidget);
        expect(storage.values[operation.scope.storageKey], blocked.encode());
        expect(repository.calls, isEmpty);
        expect(storage.writes, 0);
      },
    );
  }

  testWidgets(
    'conflict returned by recovery is reloaded and blocks further retries',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.failure = OnboardingFailure(
        OnboardingFailureKind.conflict,
        backendRejection: OnboardingBackendRejection.tryFrom(
          'IDEMPOTENCY_KEY_CONFLICT',
          409,
        ),
      );
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      expect(find.text('Retry saved registration'), findsNothing);
      expect(
        find.textContaining(
          'We cannot yet verify whether this registration was completed',
        ),
        findsOneWidget,
      );
      expect(repository.calls.single.key, operation.idempotencyKey);
      expect(getForm(), findsNothing);
    },
  );

  testWidgets(
    'recheck has loading and failure feedback without changing saved rejection',
    (tester) async {
      final operation = preparedOperation();
      final blocked = operation.withLedger(
        revision: 2,
        attempts: [
          OnboardingAttempt(
            number: 1,
            dispatchedAt: DateTime.utc(2026),
            outcome: OnboardingAttemptOutcome.rejected,
            rejection: OnboardingBackendRejection.tryFrom(
              'DUPLICATE_MEMBER_CODE',
              409,
            ),
          ),
        ],
      );
      save(blocked);
      await mount(tester);
      final reads = storage.reads;
      storage.readGate = Completer<void>();
      await Scrollable.ensureVisible(
        tester.element(find.text('Recheck saved registration')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recheck saved registration'));
      await tester.pump();
      expect(
        find.text(
          'Rechecking saved registration in secure storage. No request is being sent.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Recheck saved registration'), findsNothing);
      expect(storage.reads, reads + 1);
      storage.failRead = true;
      storage.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Latest recheck failed.'), findsOneWidget);
      expect(
        find.textContaining('Recheck failed. Secure storage'),
        findsOneWidget,
      );
      expect(
        find.text('Saved rejection: HTTP 409 · DUPLICATE_MEMBER_CODE'),
        findsOneWidget,
      );
      expect(getForm(), findsNothing);
      expect(storage.values[operation.scope.storageKey], blocked.encode());
      expect(storage.writes, 0);
      expect(repository.calls, isEmpty);
      storage.failRead = false;
      await tap(tester, 'Recheck saved registration');
      expect(
        find.textContaining(
          'Latest recheck: the saved request is still rejected.',
        ),
        findsWidgets,
      );
      expect(find.text('Secure storage could not be accessed.'), findsNothing);
      expect(storage.values[operation.scope.storageKey], blocked.encode());
      expect(repository.calls, isEmpty);
    },
  );

  for (final code in [
    'DUPLICATE_MEMBER_CODE',
    'IDEMPOTENCY_KEY_CONFLICT',
    'UNKNOWN_ERROR',
  ]) {
    testWidgets(
      'HTTP 409 $code feedback separates API outcome from storage-only recheck',
      (tester) async {
        final client = createApiClient(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        );
        addTearDown(() => client.close(force: true));
        final serverMessage = switch (code) {
          'DUPLICATE_MEMBER_CODE' => 'Member code already exists in this gym.',
          'IDEMPOTENCY_KEY_CONFLICT' =>
            'This idempotency key was already used with a different request.',
          _ =>
            'synthetic-private-token payment-reference password request-body',
        };
        final adapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': false,
            'error': {'code': code, 'message': serverMessage},
            'meta': {'requestId': 'synthetic'},
          }, status: 409),
        );
        client.httpClientAdapter = adapter;
        final operation = preparedOperation();
        save(operation);
        await mount(
          tester,
          recoveryRepository: DioMemberOnboardingRepository(client),
        );
        await tap(tester, 'Retry saved registration');
        expect(adapter.requests, hasLength(1));
        expect(find.textContaining('Latest action failed.'), findsOneWidget);
        expect(
          find.textContaining('Latest API response: HTTP 409'),
          findsOneWidget,
        );
        if (code == 'UNKNOWN_ERROR') {
          expect(find.textContaining(serverMessage), findsNothing);
          expect(find.textContaining('UNKNOWN_ERROR'), findsNothing);
          expect(find.text('Retry saved registration'), findsOneWidget);
        } else {
          expect(find.textContaining(serverMessage), findsOneWidget);
          expect(
            find.text('Saved rejection: HTTP 409 · $code'),
            findsOneWidget,
          );
          expect(find.text('Retry saved registration'), findsNothing);
        }
        final saved = storage.values[operation.scope.storageKey]!;
        final durable = PendingOnboardingOperation.decode(saved);
        expect(durable.request.frozenJson, operation.request.frozenJson);
        expect(durable.idempotencyKey, operation.idempotencyKey);
        expect(saved, isNot(contains('serverMessage')));
        await tap(tester, 'Recheck saved registration');
        expect(find.textContaining('No request was sent.'), findsWidgets);
        expect(find.textContaining('Latest API response:'), findsNothing);
        expect(adapter.requests, hasLength(1));
        expect(storage.values[operation.scope.storageKey], saved);
        expect(getForm(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unexpected recovery exception has safe feedback and preserves exact retry',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.failure = StateError('synthetic-private-token request-body');
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      expect(find.textContaining('Latest action failed.'), findsOneWidget);
      expect(
        find.textContaining('Confirmation could not be verified.'),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-private-token'), findsNothing);
      expect(getForm(), findsNothing);
      final saved = PendingOnboardingOperation.decode(
        storage.values[operation.scope.storageKey]!,
      );
      expect(saved.request.frozenJson, operation.request.frozenJson);
      expect(saved.idempotencyKey, operation.idempotencyKey);
      expect(saved.status, PendingOnboardingStatus.uncertain);
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(find.textContaining('Latest action succeeded.'), findsOneWidget);
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(repository.calls.map((call) => call.body).toSet(), {
        operation.request.frozenJson,
      });
    },
  );

  testWidgets(
    'storage read failure blocks form; explicit retry rechecks storage',
    (tester) async {
      storage.failRead = true;
      await mount(tester);
      expect(
        find.text('Secure storage could not be accessed.'),
        findsOneWidget,
      );
      expect(getForm(), findsNothing);
      storage.failRead = false;
      await tap(tester, 'Retry recovery check');
      expect(getForm(), findsOneWidget);
      expect(
        find.text('Latest recheck: no saved operation was found.'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
    },
  );

  testWidgets(
    'recheck restores newly confirmed result without POST or acknowledgement',
    (tester) async {
      final saved = confirmed();
      final unresolved = preparedOperation();
      save(unresolved);
      await mount(tester);
      container.listen(dashboardProvider, (_, _) {});
      await container.read(dashboardProvider.future);
      final dashboardReads = dashboardRepository.requests.length;
      dashboardRepository.result = GymDashboard.fromJson(
        dashboardJson(outstanding: 20000),
      );
      save(saved);
      await tap(tester, 'Recheck saved registration');
      expect(
        find.textContaining(
          'Latest recheck: the saved confirmation was verified.',
        ),
        findsWidgets,
      );
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(
        find.text('Saved state: Confirmed · Awaiting acknowledgement'),
        findsOneWidget,
      );
      expect(storage.values[saved.scope.storageKey], saved.encode());
      expect(repository.calls, isEmpty);
      expect(storage.writes, 0);
      expect(getForm(), findsNothing);
      expect(
        (await container.read(
          dashboardProvider.future,
        ))!.payments.outstandingAmountPaise,
        20000,
      );
      expect(dashboardRepository.requests.length, dashboardReads + 1);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'rejected recheck feedback fits small screen with enlarged text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 950);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final operation = preparedOperation();
        final blocked = operation.withLedger(
          revision: 2,
          attempts: [
            OnboardingAttempt(
              number: 1,
              dispatchedAt: DateTime.utc(2026),
              outcome: OnboardingAttemptOutcome.rejected,
              rejection: OnboardingBackendRejection.tryFrom(
                'DUPLICATE_MEMBER_CODE',
                409,
              ),
            ),
          ],
        );
        save(blocked);
        await mount(tester);
        await tap(tester, 'Recheck saved registration');
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byKey(const ValueKey('recoveryFeedback')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(repository.calls, isEmpty);
        expect(storage.values[operation.scope.storageKey], blocked.encode());
      },
    );
  }

  for (final unsupported in [false, true]) {
    testWidgets(
      '${unsupported ? 'unsupported' : 'corrupt'} record is retained and blocks a draft',
      (tester) async {
        final operation = preparedOperation();
        final encoded = unsupported
            ? jsonEncode({
                ...jsonDecode(operation.encode()) as Map<String, dynamic>,
                'version': 99,
              })
            : 'unreadable synthetic record';
        storage.values[operation.scope.storageKey] = encoded;
        await mount(tester);
        expect(getForm(), findsNothing);
        expect(
          find.textContaining(
            unsupported ? 'compatible app version' : 'unreadable',
          ),
          findsOneWidget,
        );
        await tap(tester, 'Retry recovery check');
        expect(storage.values[operation.scope.storageKey], encoded);
        expect(repository.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'failed dispatch persistence sends nothing and retains original identity',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      storage.failWrite = true;
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      expect(repository.calls, isEmpty);
      expect(getForm(), findsNothing);
      expect(storage.values[operation.scope.storageKey], operation.encode());
    },
  );

  testWidgets(
    'confirmation persistence failure cannot show success; replay uses original key',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.gate = Completer<OnboardingResult>();
      await mount(tester);
      await tester.tap(find.text('Retry saved registration'));
      await tester.pump();
      expect(repository.calls, hasLength(1));
      storage.failWrite = true;
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsNothing);
      expect(getForm(), findsNothing);
      storage.failWrite = false;
      repository.gate = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'acknowledgement failure preserves confirmed result and prevents fresh form',
    (tester) async {
      final operation = confirmed();
      save(operation);
      storage.failDelete = true;
      await mount(tester);
      await tap(tester, 'Acknowledge registration');
      expect(getForm(), findsNothing);
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(storage.values[operation.scope.storageKey], operation.encode());
      storage.failDelete = false;
      await tap(tester, 'Acknowledge registration');
      expect(getForm(), findsOneWidget);
      expect(repository.calls, isEmpty);
    },
  );

  testWidgets('duplicate recovery taps create only one POST', (tester) async {
    final operation = preparedOperation();
    save(operation);
    repository.gate = Completer<OnboardingResult>();
    await mount(tester);
    await tester.tap(find.text('Retry saved registration'));
    await tester.tap(find.text('Retry saved registration'));
    await tester.pump();
    expect(repository.calls, hasLength(1));
    expect(find.text('Retry saved registration'), findsNothing);
    repository.gate!.complete(
      OnboardingResult.fromJson(onboardingResultJson(operation.request)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registration confirmed'), findsOneWidget);
  });

  testWidgets(
    'gym change during secure restore hides old data and sends nothing',
    (tester) async {
      final operation = confirmed();
      save(operation);
      storage.readGate = Completer<void>();
      await mount(tester, settle: false);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pump();
      storage.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('gym context changed'), findsOneWidget);
      expect(find.text('Alex River'), findsNothing);
      expect(repository.calls, isEmpty);
      expect(storage.values[operation.scope.storageKey], operation.encode());
    },
  );

  testWidgets(
    'gym change in flight cancels recovery; no confirmation applied in new scope',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.gate = Completer<OnboardingResult>();
      await mount(tester);
      await tester.tap(find.text('Retry saved registration'));
      await tester.pump();
      expect(repository.calls, hasLength(1));
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pump();
      expect(repository.calls.single.cancel!.isCancelled, isTrue);
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      await tester.pumpAndSettle();
      final saved = PendingOnboardingOperation.decode(
        storage.values[operation.scope.storageKey]!,
      );
      expect(saved.status, PendingOnboardingStatus.uncertain);
      expect(saved.idempotencyKey, operation.idempotencyKey);
      expect(find.text('Registration confirmed'), findsNothing);
      expect(find.textContaining('gym context changed'), findsOneWidget);
      expect(storage.values, hasLength(1));
    },
  );

  testWidgets(
    'account change in flight retains old operation; new account checks its own slot',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.gate = Completer<OnboardingResult>();
      await mount(tester);
      await tester.tap(find.text('Retry saved registration'));
      await tester.pump();
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
      await tester.pump();
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.cancel!.isCancelled, isTrue);
      expect(getForm(), findsOneWidget);
      expect(find.text('Registration confirmed'), findsNothing);
      expect(storage.values, hasLength(1));
      expect(
        PendingOnboardingOperation.decode(
          storage.values[operation.scope.storageKey]!,
        ).status,
        PendingOnboardingStatus.uncertain,
      );
    },
  );

  testWidgets(
    'missing API configuration blocks draft and never checks an arbitrary slot',
    (tester) async {
      await mount(tester, url: '');
      expect(
        find.textContaining('Configure the API connection'),
        findsOneWidget,
      );
      expect(getForm(), findsNothing);
      expect(storage.reads, 0);
      expect(repository.calls, isEmpty);
    },
  );

  testWidgets(
    'reopening the route restores unresolved history and replays the original operation',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      final encoded = storage.values[operation.scope.storageKey]!;
      container.read(appRouterProvider).go(AppRoutes.members);
      await tester.pumpAndSettle();
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/new?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(getForm(), findsNothing);
      expect(storage.values[operation.scope.storageKey], encoded);
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls.map((c) => c.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(repository.calls.map((c) => c.body).toSet(), {
        operation.request.frozenJson,
      });
      final restored = PendingOnboardingOperation.decode(
        storage.values[operation.scope.storageKey]!,
      );
      expect(restored.attempts.map((a) => a.outcome), [
        OnboardingAttemptOutcome.unresolved,
        OnboardingAttemptOutcome.confirmed,
      ]);
    },
  );

  testWidgets(
    'earlier timeout followed by rejection remains recoverable, never unlocks a draft',
    (tester) async {
      final operation = preparedOperation();
      save(operation);
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await mount(tester);
      await tap(tester, 'Retry saved registration');
      repository.failure = OnboardingFailure(
        OnboardingFailureKind.conflict,
        backendRejection: OnboardingBackendRejection.tryFrom(
          'DUPLICATE_MEMBER_CODE',
          409,
        ),
      );
      await tap(tester, 'Retry saved registration');
      expect(getForm(), findsNothing);
      expect(find.text('Retry saved registration'), findsOneWidget);
      final restored = PendingOnboardingOperation.decode(
        storage.values[operation.scope.storageKey]!,
      );
      expect(restored.status, PendingOnboardingStatus.uncertain);
      expect(restored.attempts.map((a) => a.outcome), [
        OnboardingAttemptOutcome.unresolved,
        OnboardingAttemptOutcome.rejected,
      ]);
      expect(repository.calls.map((c) => c.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );

  testWidgets(
    'scope-mismatched record blocks rather than submitting another account request',
    (tester) async {
      final mismatched = preparedOperation(
        scope: onboardingScope(userId: 'other-account'),
      );
      storage.values[onboardingScope().storageKey] = mismatched.encode();
      await mount(tester);
      expect(getForm(), findsNothing);
      expect(
        find.textContaining('different account, gym or API environment'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
      expect(storage.values[onboardingScope().storageKey], mismatched.encode());
    },
  );

  testWidgets(
    'confirmed member details link retains confirmation until acknowledgement',
    (tester) async {
      final operation = confirmed();
      save(operation);
      await mount(tester);
      await tap(tester, 'View member details');
      expect(
        container.read(appRouterProvider).state.uri.path,
        '${AppRoutes.members}/${operation.result!.member.id}',
      );
      expect(storage.values[operation.scope.storageKey], operation.encode());
      expect(repository.calls, isEmpty);
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsOneWidget);
      expect(find.text('Acknowledge registration'), findsOneWidget);
      expect(getForm(), findsNothing);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'confirmed recovery fits 320px at double text scale in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 950);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        save(confirmed(membership: true, amount: 50003));
        await mount(tester);
        await tap(tester, 'Acknowledge registration');
        expect(getForm(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  PendingOnboardingOperation rejectedForCorrection({
    OnboardingBackendCode code = OnboardingBackendCode.duplicateMemberCode,
    OnboardingRequest? request,
    bool earlierUncertainty = false,
  }) {
    final operation = preparedOperation(request: request);
    return operation.withLedger(
      revision: earlierUncertainty ? 3 : 2,
      attempts: [
        if (earlierUncertainty)
          OnboardingAttempt(
            number: 1,
            dispatchedAt: DateTime.utc(2026),
            outcome: OnboardingAttemptOutcome.unresolved,
          ),
        OnboardingAttempt(
          number: earlierUncertainty ? 2 : 1,
          dispatchedAt: DateTime.utc(2026),
          outcome: code == OnboardingBackendCode.idempotencyKeyConflict
              ? OnboardingAttemptOutcome.conflict
              : OnboardingAttemptOutcome.rejected,
          rejection: OnboardingBackendRejection.tryFrom(
            code.wireValue,
            code.status,
          ),
        ),
      ],
    );
  }

  Future<void> prepareCorrectionReview(WidgetTester tester) async {
    await tap(tester, 'Correct details and retry');
    expect(repository.calls, isEmpty);
    expect((tester.widget<TextFormField>(getForm())).initialValue, 'ME01');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('firstName')))
          .initialValue,
      'Alex',
    );
    await tester.enterText(getForm(), 'ME02');
    await tap(tester, 'Continue');
    // Restored member-only choice is preserved; payment remains omitted.
    await tap(tester, 'Continue');
    expect(
      tester.widget<Text>(find.byKey(const Key('onboarding-step-title'))).data,
      'Review & Confirm',
    );
  }

  testWidgets(
    'correctable rejection opens preserved wizard and uses guarded replacement before POST',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      expect(find.text('Correct details and retry'), findsOneWidget);
      expect(
        find.textContaining('member code is already used'),
        findsOneWidget,
      );
      await tap(tester, 'Correct details and retry');
      expect(getForm(), findsOneWidget);
      await tap(tester, 'Continue');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('onboarding-step-title')))
            .data,
        'Member Details',
      );
      expect(repository.calls, isEmpty);
      expect(storage.values[original.scope.storageKey], original.encode());
      await tester.enterText(getForm(), 'ME02');
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await container.read(membersProvider.future);
      final memberReads = membersRepository.listCalls.length;
      final dashboardReads = dashboardRepository.requests.length;
      await tap(tester, 'Confirm registration');
      expect(repository.calls, hasLength(1));
      final request = jsonDecode(repository.calls.single.body) as Map;
      expect(request['member']['memberCode'], 'ME02');
      expect(request['member']['firstName'], 'Alex');
      expect(request.containsKey('membership'), isFalse);
      expect(repository.calls.single.key, isNot(original.idempotencyKey));
      // The first production-store write is the guarded prepared replacement,
      // followed by its dispatch marker and durable confirmation.
      expect(
        storage.writtenOperations.first.status,
        PendingOnboardingStatus.prepared,
      );
      expect(
        storage.writtenOperations[1].status,
        PendingOnboardingStatus.uncertain,
      );
      expect(
        storage.writtenOperations.first.idempotencyKey,
        repository.calls.single.key,
      );
      expect(find.text('Registration confirmed'), findsOneWidget);
      final confirmed = PendingOnboardingOperation.decode(
        storage.values[original.scope.storageKey]!,
      );
      expect(confirmed.result!.member.memberCode, 'ME02');
      await container.read(membersProvider.future);
      expect(membersRepository.listCalls.length, greaterThan(memberReads));
      await container.read(dashboardProvider.future);
      expect(dashboardRepository.requests.length, greaterThan(dashboardReads));
      await tap(tester, 'Acknowledge registration');
      expect(storage.values.containsKey(original.scope.storageKey), isFalse);
      expect(tester.widget<TextFormField>(getForm()).initialValue, '');
    },
  );

  testWidgets(
    'correction storage failure preserves original and retries the same replacement key/body',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      await prepareCorrectionReview(tester);
      storage.failWrite = true;
      await tap(tester, 'Confirm registration');
      expect(repository.calls, isEmpty);
      expect(storage.values[original.scope.storageKey], original.encode());
      final replacement = storage.writtenOperations.single;
      expect(find.text('Retry saving corrected registration'), findsOneWidget);
      expect(find.text('Correct details and retry'), findsNothing);
      storage.failWrite = false;
      await tap(tester, 'Retry saving corrected registration');
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.key, replacement.idempotencyKey);
      expect(repository.calls.single.body, replacement.request.frozenJson);
      expect(storage.writtenOperations[1].encode(), replacement.encode());
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate correction confirmation taps make one replacement and one POST',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      await prepareCorrectionReview(tester);
      repository.gate = Completer<OnboardingResult>();
      await Scrollable.ensureVisible(
        tester.element(find.text('Confirm registration')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm registration'));
      await tester.tap(find.text('Confirm registration'));
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(
        storage.writtenOperations.where(
          (operation) => operation.status == PendingOnboardingStatus.prepared,
        ),
        hasLength(1),
      );
      repository.gate!.complete(
        OnboardingResult.fromJson(
          onboardingResultJson(
            OnboardingRequest.fromFrozenJson(repository.calls.single.body),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain correction remains locked and exact replay retains corrected payload/key',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      await prepareCorrectionReview(tester);
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await tap(tester, 'Confirm registration');
      final first = repository.calls.single;
      expect(getForm(), findsNothing);
      expect(find.text('Correct details and retry'), findsNothing);
      expect(find.text('Retry saved registration'), findsOneWidget);
      repository.failure = null;
      await tap(tester, 'Retry saved registration');
      expect(repository.calls, hasLength(2));
      expect(repository.calls.last.body, first.body);
      expect(repository.calls.last.key, first.key);
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'earlier uncertainty plus a later duplicate-code rejection never offers correction',
    (tester) async {
      final original = rejectedForCorrection(earlierUncertainty: true);
      save(original);
      await mount(tester);
      // Ordinary member/dashboard reads have succeeded during app startup.
      await container.read(membersProvider.future);
      await tap(tester, 'Recheck saved registration');
      expect(find.text('Correct details and retry'), findsNothing);
      expect(getForm(), findsNothing);
      expect(storage.values[original.scope.storageKey], original.encode());
      expect(repository.calls, isEmpty);
      expect(find.text('Retry saved registration'), findsOneWidget);
    },
  );

  for (final code in [
    OnboardingBackendCode.idempotencyKeyConflict,
    OnboardingBackendCode.forbidden,
  ]) {
    testWidgets('${code.name} never exposes correction', (tester) async {
      final original = rejectedForCorrection(code: code);
      save(original);
      await mount(tester);
      await tap(tester, 'Recheck saved registration');
      expect(find.text('Correct details and retry'), findsNothing);
      expect(getForm(), findsNothing);
      expect(storage.values[original.scope.storageKey], original.encode());
      expect(repository.calls, isEmpty);
    });
  }

  testWidgets('legacy and unsupported fields remain locked without correction', (
    tester,
  ) async {
    final original = rejectedForCorrection(
      request: onboardingRequest(membership: true),
    );
    // An explicit start date cannot be edited by this wizard. Preserve it rather
    // than silently replacing it with the server default.
    save(original);
    await mount(tester);
    expect(find.text('Correct details and retry'), findsNothing);
    expect(getForm(), findsNothing);
    expect(storage.values[original.scope.storageKey], original.encode());
    expect(repository.calls, isEmpty);
  });

  testWidgets(
    'scope change during correction verification preserves original with no POST',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      storage.readGate = Completer<void>();
      await Scrollable.ensureVisible(
        tester.element(find.text('Correct details and retry')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct details and retry'));
      await tester.pump();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      storage.readGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      expect(storage.values[original.scope.storageKey], original.encode());
      expect(getForm(), findsNothing);
    },
  );

  OnboardingRequest paymentCorrectionRequest() {
    final body = onboardingRequest(
      membership: true,
      amount: 50003,
      method: PaymentMethod.upi,
      reference: 'OLD-REF',
    ).toJson();
    (body['membership'] as Map).remove('startDate');
    return OnboardingRequest.fromFrozenJson(jsonEncode(body));
  }

  testWidgets(
    'duplicate reference correction preserves payment and blocks reused reference',
    (tester) async {
      final original = rejectedForCorrection(
        code: OnboardingBackendCode.duplicatePaymentReference,
        request: paymentCorrectionRequest(),
      );
      save(original);
      await mount(tester);
      await tap(tester, 'Correct details and retry');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('initialPaymentAmount')),
            )
            .initialValue,
        '500.03',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('initialPaymentReference')),
            )
            .initialValue,
        'OLD-REF',
      );
      await tap(tester, 'Continue');
      expect(
        find.byKey(const ValueKey('initialPaymentAmount')),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('initialPaymentReference')),
        'NEW-REF',
      );
      await tap(tester, 'Continue');
      await tap(tester, 'Confirm registration');
      expect(repository.calls, hasLength(1));
      final payment = jsonDecode(
        repository.calls.single.body,
      )['membership']['payment'];
      expect(payment['amountPaise'], 50003);
      expect(payment['method'], 'upi');
      expect(payment['reference'], 'NEW-REF');
      expect(repository.calls.single.key, isNot(original.idempotencyKey));
      expect(find.text('Registration confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'missing-plan rejection routes to existing selection while preserving member details',
    (tester) async {
      final body = paymentCorrectionRequest().toJson();
      body['membership'] = {'planId': onboardingPlanId};
      final original = rejectedForCorrection(
        code: OnboardingBackendCode.planNotFound,
        request: OnboardingRequest.fromFrozenJson(jsonEncode(body)),
      );
      save(original);
      await mount(tester);
      await tap(tester, 'Correct details and retry');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('onboarding-step-title')))
            .data,
        'Membership Plan',
      );
      expect(find.text('Monthly'), findsOneWidget);
      await tap(tester, 'Back');
      expect(tester.widget<TextFormField>(getForm()).initialValue, 'ME01');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('phone')))
            .initialValue,
        '9876543210',
      );
      expect(storage.values[original.scope.storageKey], original.encode());
      expect(repository.calls, isEmpty);
    },
  );

  testWidgets(
    'failed authoritative verification hides correction until recheck succeeds',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      storage.failRead = true;
      await tap(tester, 'Correct details and retry');
      expect(find.text('Correct details and retry'), findsNothing);
      expect(getForm(), findsNothing);
      expect(storage.values[original.scope.storageKey], original.encode());
      storage.failRead = false;
      await tap(tester, 'Recheck saved registration');
      expect(find.text('Correct details and retry'), findsOneWidget);
      expect(repository.calls, isEmpty);
    },
  );

  testWidgets(
    'stale rejected revision cannot be replaced from a correction draft',
    (tester) async {
      final original = rejectedForCorrection();
      save(original);
      await mount(tester);
      await prepareCorrectionReview(tester);
      // A competing worker added an unresolved attempt after the editable form
      // opened. The existing store must reject the stale replacement atomically.
      final changed = original.withLedger(
        revision: 3,
        attempts: [
          ...original.attempts,
          OnboardingAttempt(
            number: 2,
            dispatchedAt: DateTime.utc(2026),
            outcome: OnboardingAttemptOutcome.unresolved,
          ),
        ],
      );
      save(changed);
      await tap(tester, 'Confirm registration');
      expect(repository.calls, isEmpty);
      expect(storage.values[original.scope.storageKey], changed.encode());
      expect(find.text('Correct details and retry'), findsNothing);
      expect(getForm(), findsNothing);
    },
  );
}
