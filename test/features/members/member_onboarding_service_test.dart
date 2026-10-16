import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_repository.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_service.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import 'onboarding_fakes.dart';

class AcknowledgementStorage extends TestOnboardingStorage {
  final readEntered = Completer<void>();
  var deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (!readEntered.isCompleted) readEntered.complete();
    return super.read(key: key);
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    deletes++;
    return super.delete(key: key);
  }
}

void main() {
  late TestOnboardingStorage platform;
  late SecurePendingOnboardingStore store;
  late FakeOnboardingRepository repository;
  late MemberOnboardingService service;
  OnboardingScope? current;
  MemberOnboardingService createService() => MemberOnboardingService(
    repository: repository,
    store: store,
    queue: OnboardingOperationQueue(),
    isAuthorized: (scope) => scope.matches(current),
  );
  setUp(() {
    platform = TestOnboardingStorage();
    store = SecurePendingOnboardingStore(
      storage: platform,
      queue: OnboardingOperationQueue(),
    );
    repository = FakeOnboardingRepository();
    current = onboardingScope();
    service = createService();
  });
  tearDown(() => service.dispose());
  Future<void> waitForCall() async {
    for (var count = 0; count < 100 && repository.calls.isEmpty; count++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repository.calls, isNotEmpty);
  }

  test(
    'HTTP diagnostics survive rejection persistence failure without fabricating durable evidence',
    () async {
      final operation = preparedOperation();
      repository.gate = Completer<OnboardingResult>();
      final submission = service.submit(operation);
      await waitForCall();
      platform.failWrite = true;
      final diagnostics = OnboardingDiagnostics.fromResponse(409, {
        'success': false,
        'error': {
          'code': 'DUPLICATE_MEMBER_CODE',
          'message': 'Member code already exists in this gym.',
        },
      });
      final assertion = expectLater(
        submission,
        throwsA(
          isA<OnboardingFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                OnboardingFailureKind.localStorage,
              )
              .having((failure) => failure.uncertain, 'uncertain', true)
              .having((failure) => failure.backendRejection, 'evidence', isNull)
              .having(
                (failure) => failure.diagnostics?.summary,
                'diagnostics',
                diagnostics.summary,
              ),
        ),
      );
      repository.gate!.completeError(
        OnboardingFailure(
          OnboardingFailureKind.conflict,
          backendRejection: OnboardingBackendRejection.tryFrom(
            'DUPLICATE_MEMBER_CODE',
            409,
          ),
          diagnostics: diagnostics,
        ),
      );
      await assertion;
      final saved = (await store.read(operation.scope))!;
      expect(
        saved.attempts.single.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
      expect(saved.attempts.single.rejection, isNull);
      expect(saved.request.frozenJson, operation.request.frozenJson);
      expect(saved.idempotencyKey, operation.idempotencyKey);
      expect(saved.encode(), isNot(contains('Member code already exists')));
    },
  );

  test(
    'persistence finishes before network write and confirmation is durable before success',
    () async {
      platform.writeGate = Completer<void>();
      platform.writeEntered = Completer<void>();
      final operation = preparedOperation();
      final future = service.submit(operation);
      await platform.writeEntered!.future;
      expect(repository.calls, isEmpty);
      platform.writeGate!.complete();
      final result = await future;
      expect(result.operationId, onboardingOperationId);
      expect(
        (await service.restore(operation.scope))!.result!.operationId,
        result.operationId,
      );
    },
  );
  test('failed persistence prevents any network request', () async {
    platform.failWrite = true;
    await expectLater(
      service.submit(preparedOperation()),
      throwsA(
        isA<OnboardingFailure>().having(
          (e) => e.kind,
          'kind',
          OnboardingFailureKind.localStorage,
        ),
      ),
    );
    expect(repository.calls, isEmpty);
  });
  test(
    'read failure also blocks writes without exposing platform details',
    () async {
      platform.failRead = true;
      await expectLater(
        service.submit(preparedOperation()),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(repository.calls, isEmpty);
    },
  );
  test(
    'timeout then process-style reconstruction reuses byte-identical body/key/time',
    () async {
      final operation = preparedOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(
        service.submit(operation),
        throwsA(isA<OnboardingFailure>()),
      );
      final retained = (await store.read(operation.scope))!;
      expect(retained.sameSubmission(operation), isTrue);
      expect(retained.status, PendingOnboardingStatus.uncertain);
      expect(
        retained.attempts.single.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
      service.dispose();
      store = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      service = createService();
      repository.failure = null;
      await service.recover(operation.scope);
      expect(repository.calls, hasLength(2));
      expect(repository.calls.map((call) => call.body).toSet(), {
        operation.request.frozenJson,
      });
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(
        (await service.restore(operation.scope))!.createdAt,
        operation.createdAt,
      );
    },
  );
  test(
    'legacy persisted microsecond operation survives retry and restart without body/key migration',
    () async {
      final body = onboardingRequest(membership: true, amount: 40000).toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final original = jsonEncode(body);
      final operation = pendingOperation(
        request: OnboardingRequest.fromFrozenJson(original),
      );
      final key = operation.idempotencyKey;
      // Seed the record as if written by the earlier app, before reconstruction.
      platform.values[operation.scope.storageKey] = operation.encode();
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(
        service.recover(operation.scope),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(platform.values[operation.scope.storageKey], operation.encode());
      expect(platform.writes, 0);

      service.dispose();
      store = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      service = createService();
      final restored = (await service.restore(operation.scope))!;
      expect(restored.request.frozenJson, original);
      expect(restored.idempotencyKey, key);
      expect(platform.writes, 0);
      repository.failure = null;
      final result = await service.recover(operation.scope);
      expect(result.payment!.paidAt, DateTime.utc(2026, 1, 1, 10, 0, 0, 123));
      expect(repository.calls.map((call) => call.body).toList(), [
        original,
        original,
      ]);
      expect(repository.calls.map((call) => call.key).toList(), [key, key]);
      final confirmedRecord =
          jsonDecode(platform.values[operation.scope.storageKey]!) as Map;
      expect(confirmedRecord['requestJson'], original);
      expect(confirmedRecord['idempotencyKey'], key);
      expect(confirmedRecord['status'], 'confirmed');

      service.dispose();
      store = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      service = createService();
      expect(
        (await service.recover(operation.scope)).operationId,
        result.operationId,
      );
      expect(repository.calls, hasLength(2));
      expect(
        (await service.restore(operation.scope))!.request.frozenJson,
        original,
      );
      expect((await service.restore(operation.scope))!.idempotencyKey, key);
    },
  );
  test(
    'post-commit confirmation storage failure preserves key for safe replay',
    () async {
      final operation = preparedOperation();
      repository.gate = Completer<OnboardingResult>();
      final future = service.submit(operation);
      await waitForCall();
      platform.failWrite = true;
      final assertion = expectLater(
        future,
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      await assertion;
      expect(
        (await store.read(operation.scope))!.status,
        PendingOnboardingStatus.uncertain,
      );
      platform.failWrite = false;
      repository.gate = null;
      await service.recover(operation.scope);
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );
  test(
    'confirmed reconstruction returns saved authoritative result without a new write',
    () async {
      final operation = preparedOperation();
      await service.submit(operation);
      service.dispose();
      service = createService();
      expect(
        (await service.recover(operation.scope)).operationId,
        onboardingOperationId,
      );
      expect(repository.calls, hasLength(1));
      await service.acknowledge((await service.restore(operation.scope))!);
      expect(await service.restore(operation.scope), isNull);
    },
  );
  test(
    'simultaneous identical submissions are serialized and reuse confirmation',
    () async {
      final operation = preparedOperation();
      final results = await Future.wait([
        service.submit(operation),
        service.submit(operation),
        service.recover(operation.scope),
      ]);
      expect(results.map((r) => r.operationId).toSet(), {
        onboardingOperationId,
      });
      expect(repository.calls, hasLength(1));
    },
  );
  test(
    'new key or changed frozen body cannot replace an unresolved operation',
    () async {
      final operation = preparedOperation();
      await store.save(operation);
      final changedJson =
          jsonDecode(operation.encode()) as Map<String, dynamic>;
      changedJson['requestJson'] = onboardingRequest(
        membership: true,
      ).frozenJson;
      final changed = PendingOnboardingOperation.decode(
        jsonEncode(changedJson),
      );
      for (final replacement in [changed, preparedOperation()]) {
        await expectLater(
          service.submit(replacement),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.kind,
              'kind',
              OnboardingFailureKind.pendingOperation,
            ),
          ),
        );
      }
      expect(repository.calls, isEmpty);
      expect(
        (await store.read(operation.scope))!.sameSubmission(operation),
        isTrue,
      );
    },
  );
  for (final kind in [
    OnboardingFailureKind.conflict,
    OnboardingFailureKind.validation,
    OnboardingFailureKind.storageUnavailable,
    OnboardingFailureKind.server,
    OnboardingFailureKind.authorization,
  ]) {
    test(
      '$kind does not discard or change pending credentials/payload',
      () async {
        final operation = preparedOperation();
        repository.failure = OnboardingFailure(kind);
        await expectLater(
          service.submit(operation),
          throwsA(isA<OnboardingFailure>()),
        );
        expect(
          (await store.read(operation.scope))!.sameSubmission(operation),
          isTrue,
        );
        expect(repository.calls, hasLength(1));
        await expectLater(
          service.acknowledge(operation),
          throwsA(isA<OnboardingFailure>()),
        );
      },
    );
  }
  for (final scenario in [
    (404, 'PLAN_NOT_FOUND', OnboardingFailureKind.resourceNotFound, false),
    (429, 'RATE_LIMITED', OnboardingFailureKind.rateLimited, false),
    (409, 'UNKNOWN_ERROR', OnboardingFailureKind.unexpectedResponse, true),
    (500, 'INTERNAL_SERVER_ERROR', OnboardingFailureKind.server, true),
  ]) {
    test(
      '${scenario.$2} retains the frozen operation for exact recovery',
      () async {
        final client = createApiClient(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        );
        addTearDown(() => client.close(force: true));
        service.dispose();
        service = MemberOnboardingService(
          repository: DioMemberOnboardingRepository(client),
          store: store,
          queue: OnboardingOperationQueue(),
          isAuthorized: (scope) => scope.matches(current),
        );
        final operation = preparedOperation(
          request: onboardingRequest(membership: true, amount: 40000),
        );
        var adapterCalls = 0;
        final adapter = CallbackAdapter((options) {
          expect(jsonEncode(options.data), operation.request.frozenJson);
          expect(options.headers['Idempotency-Key'], operation.idempotencyKey);
          if (adapterCalls++ == 0) {
            return jsonResponse(failureBody(scenario.$2), status: scenario.$1);
          }
          return jsonResponse(
            success(onboardingResultJson(operation.request)),
            status: 201,
          );
        });
        client.httpClientAdapter = adapter;
        await expectLater(
          service.submit(operation),
          throwsA(
            isA<OnboardingFailure>()
                .having((e) => e.kind, 'kind', scenario.$3)
                .having((e) => e.uncertain, 'uncertain', scenario.$4),
          ),
        );
        final durable = (await store.read(operation.scope))!;
        expect(durable.sameSubmission(operation), isTrue);
        expect(
          durable.attempts.single.outcome,
          scenario.$4
              ? OnboardingAttemptOutcome.unresolved
              : OnboardingAttemptOutcome.rejected,
        );
        expect(
          durable.status,
          scenario.$4
              ? PendingOnboardingStatus.uncertain
              : PendingOnboardingStatus.rejected,
        );
        expect(adapter.requests, hasLength(1));
        await expectLater(
          service.acknowledge(operation),
          throwsA(isA<OnboardingFailure>()),
        );
        final result = await service.recover(operation.scope);
        expect(result.operationId, onboardingOperationId);
        expect(adapter.requests, hasLength(2));
        final saved = (await store.read(operation.scope))!;
        expect(saved.request.frozenJson, operation.request.frozenJson);
        expect(saved.idempotencyKey, operation.idempotencyKey);
        expect(saved.status, PendingOnboardingStatus.confirmed);
      },
    );
  }
  test(
    'another user, gym or API scope cannot submit or see pending PII',
    () async {
      final operation = preparedOperation();
      await store.save(operation);
      for (final scope in [
        onboardingScope(userId: 'different-user'),
        onboardingScope(gymId: gymB),
        onboardingScope(url: 'https://other.example.invalid/api/v1/'),
        onboardingScope(environment: AppEnvironment.production),
      ]) {
        current = scope;
        await expectLater(
          service.submit(operation),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.kind,
              'kind',
              OnboardingFailureKind.scopeMismatch,
            ),
          ),
        );
        await expectLater(
          service.restore(operation.scope),
          throwsA(isA<OnboardingFailure>()),
        );
        expect(await service.restore(scope), isNull);
      }
      expect(repository.calls, isEmpty);
      expect(platform.values, hasLength(1));
    },
  );
  test(
    'logout during persistence prevents sending even if same actor logs in again before completion',
    () async {
      platform.writeGate = Completer<void>();
      platform.writeEntered = Completer<void>();
      final operation = preparedOperation();
      final future = service.submit(operation);
      await platform.writeEntered!.future;
      current = null;
      service.authorizationChanged();
      current = operation.scope;
      final assertion = expectLater(future, throwsA(isA<OnboardingFailure>()));
      platform.writeGate!.complete();
      await assertion;
      expect(repository.calls, isEmpty);
      expect(
        (await store.read(operation.scope))!.sameSubmission(operation),
        isTrue,
      );
    },
  );
  test(
    'logout during a request cancels delivery but retains original operation for recovery',
    () async {
      repository.gate = Completer<OnboardingResult>();
      final operation = preparedOperation();
      final future = service.submit(operation);
      await waitForCall();
      current = null;
      service.authorizationChanged();
      expect(repository.calls.single.cancel!.isCancelled, isTrue);
      final assertion = expectLater(future, throwsA(isA<OnboardingFailure>()));
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      await assertion;
      expect(
        (await store.read(operation.scope))!.status,
        PendingOnboardingStatus.uncertain,
      );
      current = operation.scope;
      repository.gate = null;
      await service.recover(operation.scope);
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );
  test(
    'account switch during restore cannot return another account data',
    () async {
      final operation = preparedOperation();
      await store.save(operation);
      platform.readGate = Completer<void>();
      final restore = service.restore(operation.scope);
      await Future<void>.delayed(Duration.zero);
      current = onboardingScope(userId: 'another-test-account');
      service.authorizationChanged();
      final assertion = expectLater(restore, throwsA(isA<OnboardingFailure>()));
      platform.readGate!.complete();
      await assertion;
      expect(platform.values, hasLength(1));
    },
  );
  test(
    'disposed service refuses queued or new work without clearing storage',
    () async {
      final operation = preparedOperation();
      await store.save(operation);
      service.dispose();
      await expectLater(
        service.recover(operation.scope),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(repository.calls, isEmpty);
      expect(platform.values, hasLength(1));
    },
  );

  for (final version in [1, 2]) {
    for (final change in [
      'account',
      'gym',
      'API',
      'environment',
      'logout',
      'logout and return',
      'dispose',
    ]) {
      test(
        'v$version $change during acknowledgement read prevents deletion',
        () async {
          final pending = version == 1
              ? pendingOperation()
              : preparedOperation();
          final result = OnboardingResult.fromJson(
            onboardingResultJson(pending.request),
          );
          final confirmed = version == 1
              ? pending.confirmed(result)
              : pending.withLedger(
                  revision: 2,
                  attempts: [
                    OnboardingAttempt(
                      number: 1,
                      dispatchedAt: DateTime.utc(2026, 1, 1),
                      outcome: OnboardingAttemptOutcome.confirmed,
                    ),
                  ],
                  result: result,
                );
          final storage = AcknowledgementStorage();
          final otherAccount = pendingOperation(
            scope: onboardingScope(userId: 'other-account'),
          );
          final otherGym = pendingOperation(
            scope: onboardingScope(gymId: gymB),
          );
          storage.values.addAll({
            confirmed.scope.storageKey: confirmed.encode(),
            otherAccount.scope.storageKey: otherAccount.encode(),
            otherGym.scope.storageKey: otherGym.encode(),
          });
          final originalRecords = Map<String, String>.of(storage.values);
          service.dispose();
          store = SecurePendingOnboardingStore(
            storage: storage,
            queue: OnboardingOperationQueue(),
          );
          service = createService();
          storage.readGate = Completer<void>();
          final acknowledgement = service.acknowledge(confirmed);
          final assertion = expectLater(
            acknowledgement,
            throwsA(
              isA<OnboardingFailure>().having(
                (failure) => failure.kind,
                'kind',
                OnboardingFailureKind.scopeMismatch,
              ),
            ),
          );
          await storage.readEntered.future;
          expect(storage.deletes, 0);
          if (change == 'dispose') {
            service.dispose();
          } else {
            current = switch (change) {
              'account' => otherAccount.scope,
              'gym' => otherGym.scope,
              'API' => onboardingScope(
                url: 'https://other.example.invalid/api/v1/',
              ),
              'environment' => onboardingScope(
                environment: AppEnvironment.production,
              ),
              _ => null,
            };
            service.authorizationChanged();
            if (change == 'logout and return') current = confirmed.scope;
          }
          storage.readGate!.complete();
          await assertion;
          expect(storage.deletes, 0);
          expect(storage.values, originalRecords);
          expect(repository.calls, isEmpty);

          // The cancelled operation cannot poison the queue or lose confirmation.
          current = confirmed.scope;
          service.dispose();
          service = createService();
          final restored = (await service.restore(confirmed.scope))!;
          expect(restored.encode(), confirmed.encode());
          await service.acknowledge(restored);
          expect(storage.deletes, 1);
          expect(storage.values, {
            otherAccount.scope.storageKey: otherAccount.encode(),
            otherGym.scope.storageKey: otherGym.encode(),
          });
          expect(repository.calls, isEmpty);
        },
      );
    }
  }
}
