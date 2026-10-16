import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_repository.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_service.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';

import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import 'onboarding_fakes.dart';

enum LedgerWriteFault { before, after, unreadable, dropped }

class LedgerStorage extends TestOnboardingStorage {
  final events = <String>[];
  final faults = <int, LedgerWriteFault>{};
  final gates = <int, Completer<void>>{};
  final entered = <int, Completer<void>>{};
  int writeCalls = 0, readCalls = 0, unreadableReads = 0;
  void Function(int)? onRead;
  void Function(int)? afterWrite;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCalls++;
    events.add('read:$readCalls');
    if (unreadableReads > 0) {
      unreadableReads--;
      throw StateError('Synthetic transient read failure');
    }
    final value = await super.read(key: key);
    onRead?.call(readCalls);
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final number = ++writeCalls;
    events.add('write:$number');
    entered[number]?.complete();
    if (gates[number] != null) await gates[number]!.future;
    final fault = faults.remove(number);
    if (fault == LedgerWriteFault.before) {
      throw StateError('Synthetic write failure');
    }
    final previous = values[key];
    await super.write(key: key, value: value);
    events.add('saved:$number');
    afterWrite?.call(number);
    if (fault == LedgerWriteFault.dropped) {
      if (previous == null) {
        values.remove(key);
      } else {
        values[key] = previous;
      }
    }
    if (fault == LedgerWriteFault.unreadable) unreadableReads = 2;
    if (fault == LedgerWriteFault.after ||
        fault == LedgerWriteFault.unreadable) {
      throw StateError('Synthetic saved write then exception');
    }
  }
}

class ObservedRepository extends FakeOnboardingRepository {
  void Function()? beforeCall;
  @override
  Future<OnboardingResult> complete(
    String gymId,
    OnboardingRequest request,
    String idempotencyKey, {
    CancelToken? cancelToken,
  }) {
    beforeCall?.call();
    return super.complete(
      gymId,
      request,
      idempotencyKey,
      cancelToken: cancelToken,
    );
  }
}

OnboardingFailure backendFailure(OnboardingBackendCode code) =>
    OnboardingFailure(
      code.kind,
      backendRejection: OnboardingBackendRejection.tryFrom(
        code.wireValue,
        code.status,
      ),
    );
Matcher fails([OnboardingFailureKind? kind]) => throwsA(
  kind == null
      ? isA<OnboardingFailure>()
      : isA<OnboardingFailure>().having((e) => e.kind, 'kind', kind),
);

void main() {
  late LedgerStorage platform;
  late SecurePendingOnboardingStore store;
  late ObservedRepository repository;
  late OnboardingOperationQueue storageQueue, submissionQueue;
  late MemberOnboardingService service;
  OnboardingScope? current;
  MemberOnboardingService makeService() => MemberOnboardingService(
    repository: repository,
    store: store,
    queue: submissionQueue,
    isAuthorized: (scope) => scope.matches(current),
  );
  setUp(() {
    platform = LedgerStorage();
    storageQueue = OnboardingOperationQueue();
    submissionQueue = OnboardingOperationQueue();
    store = SecurePendingOnboardingStore(
      storage: platform,
      queue: storageQueue,
    );
    repository = ObservedRepository();
    current = onboardingScope();
    service = makeService();
  });
  tearDown(() => service.dispose());
  PendingOnboardingOperation durable(OnboardingScope scope) =>
      PendingOnboardingOperation.decode(platform.values[scope.storageKey]!);
  Future<void> waitForCall(int count) async {
    for (var n = 0; n < 100 && repository.calls.length < count; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repository.calls, hasLength(count));
  }

  Future<PendingOnboardingOperation> rejected() async {
    final operation = preparedOperation();
    repository.failure = backendFailure(
      OnboardingBackendCode.duplicateMemberCode,
    );
    await expectLater(service.submit(operation), fails());
    repository.failure = null;
    return (await service.restore(operation.scope))!;
  }

  PendingOnboardingOperation replacement(PendingOnboardingOperation original) {
    final body = original.request.toJson();
    body['member']['memberCode'] = 'ME02';
    return PendingOnboardingOperation.create(
      scope: original.scope,
      request: OnboardingRequest.fromFrozenJson(jsonEncode(body)),
    );
  }

  test(
    'default creation is v2 prepared and dispatch is durably verified before repository',
    () async {
      final operation = preparedOperation();
      expect(operation.version, 2);
      expect(operation.status, PendingOnboardingStatus.prepared);
      platform.gates[2] = Completer<void>();
      platform.entered[2] = Completer<void>();
      repository.beforeCall = () {
        platform.events.add('network');
        final actual = durable(operation.scope);
        expect(actual.revision, 1);
        expect(actual.status, PendingOnboardingStatus.uncertain);
        expect(
          actual.attempts.single.outcome,
          OnboardingAttemptOutcome.unresolved,
        );
        expect(
          platform.events[platform.events.length - 2],
          startsWith('read:'),
        );
      };
      final future = service.submit(operation);
      await platform.entered[2]!.future;
      expect(durable(operation.scope).status, PendingOnboardingStatus.prepared);
      expect(repository.calls, isEmpty);
      platform.gates[2]!.complete();
      final result = await future;
      expect(durable(operation.scope).result!.operationId, result.operationId);
      expect(durable(operation.scope).revision, 2);
      expect(
        platform.events.indexOf('saved:2'),
        lessThan(platform.events.indexOf('network')),
      );
    },
  );

  for (final fault in LedgerWriteFault.values) {
    test('dispatch marker $fault never invokes repository', () async {
      final operation = preparedOperation();
      platform.faults[2] = fault;
      await expectLater(service.submit(operation), fails());
      expect(repository.calls, isEmpty);
      final actual = durable(operation.scope);
      expect(actual.sameSubmission(operation), isTrue);
      expect(actual.attempts.every((a) => a.rejection == null), isTrue);
    });
  }

  test(
    'same-process and restart retries append markers and preserve exact body and key',
    () async {
      final operation = preparedOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(service.submit(operation), fails());
      await expectLater(service.recover(operation.scope), fails());
      final unknown = durable(operation.scope);
      expect(unknown.attempts.map((a) => a.number), [1, 2]);
      expect(
        unknown.attempts.every(
          (a) => a.outcome == OnboardingAttemptOutcome.unresolved,
        ),
        isTrue,
      );
      service.dispose();
      storageQueue = OnboardingOperationQueue();
      submissionQueue = OnboardingOperationQueue();
      store = SecurePendingOnboardingStore(
        storage: platform,
        queue: storageQueue,
      );
      service = makeService();
      repository.failure = null;
      await service.recover(operation.scope);
      expect(repository.calls.map((call) => call.body).toSet(), {
        operation.request.frozenJson,
      });
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
      expect(durable(operation.scope).createdAt, operation.createdAt);
      expect(durable(operation.scope).attempts.map((a) => a.number), [1, 2, 3]);
      expect(
        durable(operation.scope).attempts.last.outcome,
        OnboardingAttemptOutcome.confirmed,
      );
    },
  );

  test(
    'timeout then rejection retains uncertainty and blocks correction',
    () async {
      final operation = preparedOperation();
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(service.submit(operation), fails());
      repository.failure = backendFailure(
        OnboardingBackendCode.duplicateMemberCode,
      );
      await expectLater(
        service.recover(operation.scope),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.uncertain,
            'whole history uncertain',
            true,
          ),
        ),
      );
      final actual = (await service.restore(operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.uncertain);
      expect(actual.attempts.first.rejection, isNull);
      expect(
        actual.attempts.last.rejection!.code,
        OnboardingBackendCode.duplicateMemberCode,
      );
      await expectLater(service.correct(actual, replacement(actual)), fails());
      expect(durable(actual.scope).encode(), actual.encode());
      expect(repository.calls, hasLength(2));
    },
  );

  for (final code in [
    OnboardingBackendCode.duplicateMemberCode,
    OnboardingBackendCode.planNotFound,
    OnboardingBackendCode.rateLimited,
    OnboardingBackendCode.onboardingStorageUnavailable,
  ]) {
    test(
      'first $code permits correction only after durable rejection',
      () async {
        final operation = preparedOperation();
        repository.failure = backendFailure(code);
        await expectLater(
          service.submit(operation),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              false,
            ),
          ),
        );
        final actual = (await service.restore(operation.scope))!;
        expect(actual.status, PendingOnboardingStatus.rejected);
        expect(actual.attempts.single.rejection!.code, code);
        final corrected = replacement(actual);
        final saved = await service.correct(actual, corrected);
        expect(saved.encode(), corrected.encode());
        expect(repository.calls, hasLength(1));
        expect(saved.idempotencyKey, isNot(operation.idempotencyKey));
        repository.failure = null;
        await service.submit(saved);
        expect(repository.calls.last.key, corrected.idempotencyKey);
        expect(repository.calls.last.body, corrected.request.frozenJson);
        expect(durable(saved.scope).status, PendingOnboardingStatus.confirmed);
      },
    );
  }

  test(
    'failed rejection persistence provides no eligibility and retry preserves uncertainty',
    () async {
      final operation = preparedOperation();
      repository.failure = backendFailure(
        OnboardingBackendCode.duplicateMemberCode,
      );
      platform.faults[3] = LedgerWriteFault.before;
      await expectLater(
        service.submit(operation),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final unknown = (await service.restore(operation.scope))!;
      expect(unknown.attempts.single.rejection, isNull);
      await expectLater(
        service.correct(unknown, replacement(unknown)),
        fails(),
      );
      await expectLater(service.recover(operation.scope), fails());
      expect(
        durable(operation.scope).status,
        PendingOnboardingStatus.uncertain,
      );
      expect(durable(operation.scope).attempts, hasLength(2));
    },
  );

  for (final uncertain in [false, true]) {
    test(
      'idempotency conflict uncertain=$uncertain always requires reconciliation',
      () async {
        final operation = preparedOperation();
        repository.failure = OnboardingFailure(
          OnboardingFailureKind.conflict,
          uncertain: uncertain,
          backendRejection: OnboardingBackendRejection.tryFrom(
            'IDEMPOTENCY_KEY_CONFLICT',
            409,
          ),
        );
        await expectLater(
          service.submit(operation),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
        final actual = (await service.restore(operation.scope))!;
        expect(actual.status, PendingOnboardingStatus.reconciliationRequired);
        await expectLater(
          service.correct(actual, replacement(actual)),
          fails(),
        );
        await expectLater(service.recover(operation.scope), fails());
        expect(repository.calls, hasLength(1));
      },
    );
  }

  for (final kind in [
    OnboardingFailureKind.validation,
    OnboardingFailureKind.authorization,
    OnboardingFailureKind.server,
    OnboardingFailureKind.network,
    OnboardingFailureKind.configuration,
    OnboardingFailureKind.localStorage,
    OnboardingFailureKind.conflict,
    OnboardingFailureKind.unexpectedResponse,
  ]) {
    test(
      'generic $kind supplies no non-commit evidence even with uncertain=false',
      () async {
        final operation = preparedOperation();
        repository.failure = OnboardingFailure(kind);
        await expectLater(
          service.submit(operation),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
        final actual = (await service.restore(operation.scope))!;
        expect(actual.status, PendingOnboardingStatus.uncertain);
        expect(actual.attempts.single.rejection, isNull);
        await expectLater(
          service.correct(actual, replacement(actual)),
          fails(),
        );
      },
    );
  }

  for (final kind in AuthFailureKind.values) {
    test('wrapped auth $kind cannot release an operation', () async {
      final operation = preparedOperation();
      repository.failure = OnboardingFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(),
          error: AuthFailure(kind),
        ),
      );
      await expectLater(service.submit(operation), fails());
      final actual = (await service.restore(operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.uncertain);
      expect(actual.attempts.single.rejection, isNull);
      await expectLater(service.correct(actual, replacement(actual)), fails());
    });
  }

  test(
    'unknown thrown exception is safe and leaves no rejection evidence',
    () async {
      final operation = preparedOperation();
      repository.failure = StateError('Synthetic unrelated exception');
      await expectLater(
        service.submit(operation),
        fails(OnboardingFailureKind.unexpectedResponse),
      );
      expect(
        durable(operation.scope).status,
        PendingOnboardingStatus.uncertain,
      );
      expect(durable(operation.scope).attempts.single.rejection, isNull);
    },
  );

  test(
    'successful but wrong-scope response is unconfirmed and recoverable',
    () async {
      final operation = preparedOperation();
      repository.gate = Completer<OnboardingResult>();
      final future = service.submit(operation);
      await waitForCall(1);
      final assertion = expectLater(
        future,
        fails(OnboardingFailureKind.unexpectedResponse),
      );
      repository.gate!.complete(
        OnboardingResult.fromJson(
          onboardingResultJson(operation.request, gymId: gymB),
        ),
      );
      await assertion;
      expect(durable(operation.scope).result, isNull);
      expect(
        durable(operation.scope).status,
        PendingOnboardingStatus.uncertain,
      );
    },
  );

  test(
    'failed confirmation write retains original key and permits successful replay',
    () async {
      final operation = preparedOperation();
      platform.faults[3] = LedgerWriteFault.before;
      await expectLater(
        service.submit(operation),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final actual = (await service.restore(operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.uncertain);
      await expectLater(service.correct(actual, replacement(actual)), fails());
      await service.recover(operation.scope);
      expect(repository.calls.map((c) => c.key).toList(), [
        operation.idempotencyKey,
        operation.idempotencyKey,
      ]);
      expect(
        durable(operation.scope).attempts.first.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
      expect(
        durable(operation.scope).attempts.last.outcome,
        OnboardingAttemptOutcome.confirmed,
      );
    },
  );

  test(
    'confirmation saved then thrown write returns only verified durable success',
    () async {
      final operation = preparedOperation();
      platform.faults[3] = LedgerWriteFault.after;
      final result = await service.submit(operation);
      expect(durable(operation.scope).result!.operationId, result.operationId);
      await service.recover(operation.scope);
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'unreadable confirmation write restores durable success without resubmission',
    () async {
      final operation = preparedOperation();
      platform.faults[3] = LedgerWriteFault.unreadable;
      await expectLater(service.submit(operation), fails());
      final actual = (await service.restore(operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.confirmed);
      service.dispose();
      service = makeService();
      await service.recover(operation.scope);
      expect(repository.calls, hasLength(1));
      await expectLater(service.correct(actual, replacement(actual)), fails());
      await service.acknowledge(actual);
      expect(platform.values, isEmpty);
    },
  );

  test(
    'fallback read can verify confirmation after a transient verification failure',
    () async {
      final operation = preparedOperation();
      platform.afterWrite = (number) {
        if (number == 3) platform.unreadableReads = 1;
      };
      final result = await service.submit(operation);
      expect(durable(operation.scope).result!.operationId, result.operationId);
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'scope change during marker read prevents its write and all network calls',
    () async {
      final operation = preparedOperation();
      await store.save(operation);
      platform.readCalls = 0;
      platform.onRead = (number) {
        if (number == 2) {
          current = null;
          service.authorizationChanged();
        }
      };
      await expectLater(
        service.submit(operation),
        fails(OnboardingFailureKind.scopeMismatch),
      );
      expect(repository.calls, isEmpty);
      expect(durable(operation.scope).status, PendingOnboardingStatus.prepared);
    },
  );

  test(
    'scope loss after saved marker retires handle without non-commit evidence',
    () async {
      final operation = preparedOperation();
      platform.afterWrite = (number) {
        if (number == 2) {
          current = null;
          service.authorizationChanged();
        }
      };
      await expectLater(
        service.submit(operation),
        fails(OnboardingFailureKind.scopeMismatch),
      );
      expect(repository.calls, isEmpty);
      expect(durable(operation.scope).attempts.single.rejection, isNull);
      platform.afterWrite = null;
      current = operation.scope;
      await service.recover(operation.scope);
      expect(durable(operation.scope).attempts, hasLength(2));
      expect(repository.calls, hasLength(1));
    },
  );

  for (final rejectedResponse in [false, true]) {
    test(
      'scope loss before outcome persistence protects pending history ($rejectedResponse)',
      () async {
        final operation = preparedOperation();
        if (rejectedResponse) {
          repository.failure = backendFailure(
            OnboardingBackendCode.duplicateMemberCode,
          );
        }
        repository.beforeCall = () {
          platform.onRead = (_) {
            current = null;
            service.authorizationChanged();
          };
        };
        await expectLater(
          service.submit(operation),
          fails(OnboardingFailureKind.scopeMismatch),
        );
        expect(durable(operation.scope).revision, 1);
        expect(durable(operation.scope).attempts.single.rejection, isNull);
        expect(durable(operation.scope).result, isNull);
        platform.onRead = null;
        repository.beforeCall = null;
        repository.failure = null;
        current = operation.scope;
        await service.recover(operation.scope);
        expect(durable(operation.scope).attempts, hasLength(2));
      },
    );
  }

  test(
    'cancellation after dispatch does not record even a late typed rejection',
    () async {
      final operation = preparedOperation();
      repository.gate = Completer<OnboardingResult>();
      final future = service.submit(operation);
      await waitForCall(1);
      current = null;
      service.authorizationChanged();
      expect(repository.calls.single.cancel!.isCancelled, isTrue);
      final assertion = expectLater(
        future,
        fails(OnboardingFailureKind.scopeMismatch),
      );
      repository.gate!.completeError(
        backendFailure(OnboardingBackendCode.duplicateMemberCode),
      );
      await assertion;
      expect(durable(operation.scope).attempts.single.rejection, isNull);
      current = operation.scope;
      repository.gate = null;
      await service.recover(operation.scope);
      expect(durable(operation.scope).attempts, hasLength(2));
    },
  );

  test(
    'concurrent submissions and recovery reuse one durable confirmation',
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
      expect(durable(operation.scope).attempts, hasLength(1));
    },
  );

  test(
    'correction wins over a queued stale retry without sending old payload',
    () async {
      final old = await rejected();
      final corrected = replacement(old);
      final correction = service.correct(old, corrected);
      final retry = service.submit(old);
      await expectLater(retry, fails());
      expect((await correction).encode(), corrected.encode());
      expect(repository.calls, hasLength(1));
      await service.submit(corrected);
      expect(repository.calls.last.key, corrected.idempotencyKey);
    },
  );

  test(
    'retry wins over stale correction and preserves confirmed operation',
    () async {
      final old = await rejected();
      final retry = service.recover(old.scope);
      final correction = service.correct(old, replacement(old));
      await expectLater(correction, fails());
      await retry;
      expect(durable(old.scope).status, PendingOnboardingStatus.confirmed);
      expect(durable(old.scope).idempotencyKey, old.idempotencyKey);
    },
  );

  test(
    'concurrent corrections cannot replace the winning prepared operation',
    () async {
      final old = await rejected();
      final first = replacement(old), second = replacement(old);
      final winner = service.correct(old, first);
      final loser = service.correct(old, second);
      await expectLater(loser, fails());
      expect((await winner).encode(), first.encode());
      expect(durable(old.scope).encode(), first.encode());
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'correction restoration retains one replacement key after saved-but-unreadable write',
    () async {
      final old = await rejected();
      final corrected = replacement(old);
      platform.faults[4] = LedgerWriteFault.unreadable;
      await expectLater(service.correct(old, corrected), fails());
      platform.unreadableReads = 0;
      await expectLater(service.correct(old, corrected), fails());
      final saved = (await service.restore(old.scope))!;
      expect(saved.sameSubmission(corrected), isTrue);
      expect(saved.idempotencyKey, corrected.idempotencyKey);
      expect(platform.writeCalls, 4);
      expect(repository.calls, hasLength(1));
      await service.submit(saved);
      expect(repository.calls.last.key, corrected.idempotencyKey);
    },
  );

  test(
    'correction refuses different scope and scope loss during its authoritative read',
    () async {
      final old = await rejected();
      final other = preparedOperation(scope: onboardingScope(gymId: gymB));
      await expectLater(
        service.correct(old, other),
        fails(OnboardingFailureKind.scopeMismatch),
      );
      final corrected = replacement(old);
      final baseline = platform.readCalls;
      platform.onRead = (number) {
        if (number == baseline + 1) {
          current = null;
          service.authorizationChanged();
        }
      };
      await expectLater(
        service.correct(old, corrected),
        fails(OnboardingFailureKind.scopeMismatch),
      );
      expect(durable(old.scope).encode(), old.encode());
    },
  );

  test(
    'failed correction before writing retries the same prepared body and key',
    () async {
      final old = await rejected();
      final corrected = replacement(old);
      platform.faults[4] = LedgerWriteFault.before;
      await expectLater(service.correct(old, corrected), fails());
      expect(durable(old.scope).encode(), old.encode());
      final saved = await service.correct(old, corrected);
      expect(saved.encode(), corrected.encode());
      expect(saved.idempotencyKey, corrected.idempotencyKey);
      expect(repository.calls, hasLength(1));
    },
  );

  test('stale callbacks cannot overwrite a newer operation identity', () async {
    final operation = preparedOperation();
    repository.gate = Completer<OnboardingResult>();
    final future = service.submit(operation);
    await waitForCall(1);
    // Simulate a stale callback after an external storage change. The shared
    // queue never permits this replacement itself; verify the identity guard.
    final newer = preparedOperation();
    platform.values[operation.scope.storageKey] = newer.encode();
    final assertion = expectLater(future, fails());
    repository.gate!.complete(
      OnboardingResult.fromJson(onboardingResultJson(operation.request)),
    );
    await assertion;
    expect(durable(operation.scope).encode(), newer.encode());
    repository.gate = null;
    await service.submit(newer);
    expect(durable(newer.scope).idempotencyKey, newer.idempotencyKey);
  });

  test(
    'provider-style service replacement shares submission queue and retires cancelled handles',
    () async {
      final operation = preparedOperation();
      repository.gate = Completer<OnboardingResult>();
      final future = service.submit(operation);
      await waitForCall(1);
      service.dispose();
      final replacementService = makeService();
      final recovery = replacementService.recover(operation.scope);
      final assertion = expectLater(
        future,
        fails(OnboardingFailureKind.scopeMismatch),
      );
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      repository.gate = null;
      await assertion;
      await recovery;
      service = replacementService;
      expect(durable(operation.scope).attempts, hasLength(2));
      expect(repository.calls.map((c) => c.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );

  test(
    'newly fabricated legacy submissions are refused without storage or network writes',
    () async {
      await expectLater(
        service.submit(pendingOperation()),
        fails(OnboardingFailureKind.pendingOperation),
      );
      expect(platform.values, isEmpty);
      expect(repository.calls, isEmpty);
    },
  );

  test(
    'legacy exact encoding, microseconds and key survive rejection and remain uncorrectable',
    () async {
      final old = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      final body = old.request.toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final json = jsonDecode(old.encode()) as Map<String, dynamic>;
      json['requestJson'] = const JsonEncoder.withIndent('  ').convert(body);
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      json['idempotencyKey'] = 'Legacy_Original-Key12345';
      final encoded = const JsonEncoder.withIndent('  ').convert(json);
      platform.values[old.scope.storageKey] = encoded;
      repository.failure = backendFailure(
        OnboardingBackendCode.duplicateMemberCode,
      );
      final restored = (await service.restore(old.scope))!;
      await expectLater(service.submit(restored), fails());
      expect(platform.values[old.scope.storageKey], encoded);
      expect(platform.writes, 0);
      await expectLater(
        service.correct(restored, replacement(restored)),
        fails(),
      );
      repository.failure = null;
      await service.recover(old.scope);
      final confirmed = durable(old.scope);
      expect(confirmed.version, 1);
      expect(confirmed.attempts, isEmpty);
      expect(confirmed.request.frozenJson, json['requestJson']);
      expect(confirmed.idempotencyKey, json['idempotencyKey']);
      expect(jsonDecode(confirmed.encode())['createdAt'], json['createdAt']);
      expect(repository.calls.map((call) => call.body).toSet(), {
        json['requestJson'],
      });
      await service.recover(old.scope);
      expect(repository.calls, hasLength(2));
    },
  );

  for (final scenario in [
    (404, 'PLAN_NOT_FOUND', true),
    (429, 'RATE_LIMITED', true),
    (500, 'PLAN_NOT_FOUND', false),
    (409, 'UNKNOWN_ERROR', false),
  ]) {
    test(
      'real repository ${scenario.$1}/${scenario.$2} persists only verified evidence',
      () async {
        final client = createApiClient(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        );
        addTearDown(() => client.close(force: true));
        service.dispose();
        service = MemberOnboardingService(
          repository: DioMemberOnboardingRepository(client),
          store: store,
          queue: submissionQueue,
          isAuthorized: (scope) => scope.matches(current),
        );
        final operation = preparedOperation();
        client.httpClientAdapter = CallbackAdapter((options) {
          expect(
            durable(operation.scope).attempts.single.outcome,
            OnboardingAttemptOutcome.unresolved,
          );
          expect(options.headers['Idempotency-Key'], operation.idempotencyKey);
          return jsonResponse(failureBody(scenario.$2), status: scenario.$1);
        });
        await expectLater(service.submit(operation), fails());
        final actual = (await service.restore(operation.scope))!;
        expect(actual.attempts.single.rejection != null, scenario.$3);
        expect(
          actual.status,
          scenario.$3
              ? PendingOnboardingStatus.rejected
              : PendingOnboardingStatus.uncertain,
        );
      },
    );
  }
}
