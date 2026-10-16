import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';

import '../admin_dashboard/dashboard_fakes.dart';
import 'onboarding_fakes.dart';

enum WriteFault { before, after, unreadable, dropped, corrupt }

class TransitionStorage extends TestOnboardingStorage {
  WriteFault? fault;
  Completer<void>? verificationGate;
  Completer<void>? verificationEntered;
  bool _verifying = false;

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
    final failure = fault;
    fault = null;
    final previous = values[key];
    if (failure == WriteFault.before) {
      throw StateError('Synthetic failed write');
    }
    await super.write(key: key, value: value);
    if (verificationGate != null) _verifying = true;
    if (failure == WriteFault.dropped) {
      if (previous == null) {
        values.remove(key);
      } else {
        values[key] = previous;
      }
    }
    if (failure == WriteFault.corrupt) values[key] = 'not-json';
    if (failure == WriteFault.unreadable) failRead = true;
    if (failure == WriteFault.after || failure == WriteFault.unreadable) {
      throw StateError('Synthetic write succeeded then threw');
    }
  }

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
    if (_verifying) {
      verificationEntered?.complete();
      await verificationGate!.future;
      _verifying = false;
    }
    return super.read(key: key);
  }
}

PendingOnboardingOperation prepared({OnboardingScope? scope}) =>
    PendingOnboardingOperation.prepared(
      scope: scope ?? onboardingScope(),
      request: onboardingRequest(),
    );

OnboardingBackendRejection get rejection =>
    OnboardingBackendRejection.tryFrom('DUPLICATE_MEMBER_CODE', 409)!;
OnboardingBackendRejection get conflict =>
    OnboardingBackendRejection.tryFrom('IDEMPOTENCY_KEY_CONFLICT', 409)!;
OnboardingResult resultFor(PendingOnboardingOperation operation) =>
    OnboardingResult.fromJson(onboardingResultJson(operation.request));

Matcher failure([OnboardingFailureKind? kind]) => throwsA(
  kind == null
      ? isA<OnboardingFailure>()
      : isA<OnboardingFailure>().having((e) => e.kind, 'kind', kind),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitionStorage platform;
  late OnboardingOperationQueue queue;
  late SecurePendingOnboardingStore store;
  setUp(() {
    platform = TransitionStorage();
    queue = OnboardingOperationQueue();
    store = SecurePendingOnboardingStore(storage: platform, queue: queue);
  });
  Future<OnboardingDispatch> dispatch(PendingOnboardingOperation operation) =>
      store.markDispatched(
        operation,
        attemptNumber: operation.attempts.length + 1,
        dispatchedAt: DateTime.utc(2026, 10, 9, 10),
      );
  Future<PendingOnboardingOperation> reject(OnboardingDispatch handle) =>
      store.recordAttemptOutcome(
        handle,
        attemptNumber: handle.attemptNumber,
        outcome: OnboardingAttemptOutcome.rejected,
        rejection: rejection,
      );
  Future<PendingOnboardingOperation> rejected() async {
    final operation = await store.save(prepared());
    return reject(await dispatch(operation));
  }

  test('new prepared operations opt in without changing legacy creation', () {
    final operation = prepared();
    expect(operation.version, 2);
    expect(operation.revision, 0);
    expect(operation.status, PendingOnboardingStatus.prepared);
    expect(operation.attempts, isEmpty);
    expect(pendingOperation().version, 1);
    expect(operation.scope.storageKey, pendingOperation().scope.storageKey);
    expect(
      PendingOnboardingOperation.decode(operation.encode()).encode(),
      operation.encode(),
    );
  });

  test(
    'send permission waits for both marker write and authoritative read-back',
    () async {
      final operation = await store.save(prepared());
      platform.writeGate = Completer<void>();
      platform.writeEntered = Completer<void>();
      platform.verificationGate = Completer<void>();
      platform.verificationEntered = Completer<void>();
      var allowedToSend = false;
      final pending = dispatch(operation).then((handle) {
        allowedToSend = true;
        final stored = PendingOnboardingOperation.decode(
          platform.values[operation.scope.storageKey]!,
        );
        expect(stored.revision, 1);
        expect(
          stored.attempts.single.outcome,
          OnboardingAttemptOutcome.unresolved,
        );
        return handle;
      });
      await platform.writeEntered!.future;
      expect(allowedToSend, isFalse);
      platform.writeGate!.complete();
      await platform.verificationEntered!.future;
      expect(allowedToSend, isFalse);
      platform.verificationGate!.complete();
      final handle = await pending;
      expect(allowedToSend, isTrue);
      expect(handle.attemptNumber, 1);
    },
  );

  for (final fault in WriteFault.values) {
    test('marker $fault never issues send permission', () async {
      final operation = await store.save(prepared());
      platform.fault = fault;
      await expectLater(dispatch(operation), failure());
      platform.failRead = false;
      final raw = platform.values[operation.scope.storageKey]!;
      if (fault == WriteFault.corrupt) {
        expect(raw, 'not-json');
      } else {
        final actual = (await store.read(operation.scope))!;
        expect(
          actual.status,
          fault == WriteFault.before || fault == WriteFault.dropped
              ? PendingOnboardingStatus.prepared
              : PendingOnboardingStatus.uncertain,
        );
        expect(actual.attempts.every((a) => a.rejection == null), isTrue);
      }
    });
  }

  test(
    'unverifiable initial storage blocks dispatch without writing',
    () async {
      final operation = await store.save(prepared());
      final writes = platform.writes;
      platform.failRead = true;
      await expectLater(
        dispatch(operation),
        failure(OnboardingFailureKind.localStorage),
      );
      expect(platform.writes, writes);
    },
  );

  test(
    'wrong marker identity, revision and number cannot mutate storage',
    () async {
      final operation = await store.save(prepared());
      final bytes = platform.values[operation.scope.storageKey];
      await expectLater(
        dispatch(prepared()),
        failure(OnboardingFailureKind.pendingOperation),
      );
      await expectLater(
        store.markDispatched(
          operation,
          attemptNumber: 2,
          dispatchedAt: DateTime.utc(2026),
        ),
        failure(OnboardingFailureKind.pendingOperation),
      );
      expect(platform.values[operation.scope.storageKey], bytes);
      final handle = await dispatch(operation);
      await expectLater(
        dispatch(operation),
        failure(OnboardingFailureKind.pendingOperation),
      );
      expect(
        (await store.read(operation.scope))!.encode(),
        handle.operation.encode(),
      );
    },
  );

  test('invalid dispatch time produces no marker or send permission', () async {
    final operation = await store.save(prepared());
    await expectLater(
      store.markDispatched(
        operation,
        attemptNumber: 1,
        dispatchedAt: DateTime(2026),
      ),
      failure(OnboardingFailureKind.validation),
    );
    expect((await store.read(operation.scope))!.attempts, isEmpty);
  });

  test(
    'concurrent dispatch and provider replacement share one live handle',
    () async {
      final operation = await store.save(prepared());
      final other = SecurePendingOnboardingStore(
        storage: platform,
        queue: queue,
      );
      final first = dispatch(operation);
      final second = other.markDispatched(
        operation,
        attemptNumber: 1,
        dispatchedAt: DateTime.utc(2026),
      );
      await expectLater(
        second,
        failure(OnboardingFailureKind.pendingOperation),
      );
      final handle = await first;
      await expectLater(
        other.markDispatched(
          handle.operation,
          attemptNumber: 2,
          dispatchedAt: DateTime.utc(2026),
        ),
        failure(OnboardingFailureKind.pendingOperation),
      );
      final completed = await other.recordAttemptOutcome(
        handle,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.rejected,
        rejection: rejection,
      );
      expect(completed.status, PendingOnboardingStatus.rejected);
    },
  );

  test(
    'wrong queue and wrong outcome number cannot close a live attempt',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      final other = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      await expectLater(
        other.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: OnboardingAttemptOutcome.rejected,
          rejection: rejection,
        ),
        failure(),
      );
      await expectLater(
        store.recordAttemptOutcome(
          handle,
          attemptNumber: 2,
          outcome: OnboardingAttemptOutcome.rejected,
          rejection: rejection,
        ),
        failure(),
      );
      expect((await store.read(handle.operation.scope))!.revision, 1);
      expect((await reject(handle)).revision, 2);
    },
  );

  test(
    'stale outcome revision cannot overwrite newer authoritative storage',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      final advanced = handle.operation.withLedger(
        revision: 2,
        attempts: handle.operation.attempts,
      );
      platform.values[advanced.scope.storageKey] = advanced.encode();
      await expectLater(
        reject(handle),
        failure(OnboardingFailureKind.pendingOperation),
      );
      expect(platform.values[advanced.scope.storageKey], advanced.encode());
    },
  );

  test(
    'outcome identity and attempt number are checked against actual storage',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      final other = prepared();
      platform.values[other.scope.storageKey] = other.encode();
      await expectLater(
        reject(handle),
        failure(OnboardingFailureKind.pendingOperation),
      );
      expect(platform.values[other.scope.storageKey], other.encode());
    },
  );

  for (final outcome in OnboardingAttemptOutcome.values) {
    test('$outcome requires its exact typed evidence/result shape', () async {
      final handle = await dispatch(await store.save(prepared()));
      await expectLater(
        store.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: outcome,
          rejection: outcome == OnboardingAttemptOutcome.rejected
              ? conflict
              : rejection,
        ),
        failure(OnboardingFailureKind.validation),
      );
      expect((await store.read(handle.operation.scope))!.revision, 1);
      expect((await reject(handle)).status, PendingOnboardingStatus.rejected);
    });
  }

  test('confirmed result must match the immutable request and scope', () async {
    final handle = await dispatch(await store.save(prepared()));
    final wrong = OnboardingResult.fromJson(
      onboardingResultJson(handle.operation.request, gymId: gymB),
    );
    await expectLater(
      store.recordAttemptOutcome(
        handle,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.confirmed,
        result: wrong,
      ),
      failure(OnboardingFailureKind.validation),
    );
    expect((await store.read(handle.operation.scope))!.result, isNull);
  });

  test(
    'duplicate concurrent outcomes are single use and cannot change rejection',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      final first = reject(handle);
      final second = store.recordAttemptOutcome(
        handle,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.confirmed,
        result: resultFor(handle.operation),
      );
      await expectLater(
        second,
        failure(OnboardingFailureKind.pendingOperation),
      );
      final actual = await first;
      expect(actual.status, PendingOnboardingStatus.rejected);
      expect(
        actual.attempts.single.rejection!.code,
        OnboardingBackendCode.duplicateMemberCode,
      );
    },
  );

  test(
    'failed rejection persistence stays unresolved and handle cannot be reused',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      platform.fault = WriteFault.before;
      await expectLater(
        reject(handle),
        failure(OnboardingFailureKind.localStorage),
      );
      final actual = (await store.read(handle.operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.uncertain);
      expect(actual.attempts.single.rejection, isNull);
      await expectLater(reject(handle), failure());
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 1),
        failure(),
      );
    },
  );

  test(
    'failed outcome read consumes handle and leaves no rejection evidence',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      platform.failRead = true;
      await expectLater(
        reject(handle),
        failure(OnboardingFailureKind.localStorage),
      );
      platform.failRead = false;
      await expectLater(reject(handle), failure());
      expect(
        (await store.read(handle.operation.scope))!.attempts.single.rejection,
        isNull,
      );
    },
  );

  for (final outcome in [
    OnboardingAttemptOutcome.rejected,
    OnboardingAttemptOutcome.confirmed,
  ]) {
    test(
      '$outcome write-then-throw is resolved only by exact read-back',
      () async {
        final handle = await dispatch(await store.save(prepared()));
        platform.fault = WriteFault.after;
        final actual = await store.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: outcome,
          rejection: outcome == OnboardingAttemptOutcome.rejected
              ? rejection
              : null,
          result: outcome == OnboardingAttemptOutcome.confirmed
              ? resultFor(handle.operation)
              : null,
        );
        expect(actual.revision, 2);
        expect(actual.attempts.single.outcome, outcome);
        expect(platform.values[actual.scope.storageKey], actual.encode());
        await expectLater(reject(handle), failure());
      },
    );
  }

  test(
    'failed confirmation write leaves an unresolved operation blocked',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      platform.fault = WriteFault.before;
      await expectLater(
        store.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: OnboardingAttemptOutcome.confirmed,
          result: resultFor(handle.operation),
        ),
        failure(),
      );
      final actual = (await store.read(handle.operation.scope))!;
      expect(actual.result, isNull);
      expect(actual.status, PendingOnboardingStatus.uncertain);
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 1),
        failure(),
      );
    },
  );

  test(
    'unreadable confirmation write preserves result for restart and acknowledgement',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      platform.fault = WriteFault.unreadable;
      await expectLater(
        store.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: OnboardingAttemptOutcome.confirmed,
          result: resultFor(handle.operation),
        ),
        failure(),
      );
      platform.failRead = false;
      final restarted = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      final actual = (await restarted.read(handle.operation.scope))!;
      expect(actual.status, PendingOnboardingStatus.confirmed);
      expect(actual.result!.operationId, onboardingOperationId);
      expect(
        (await restarted.save(handle.operation)).encode(),
        actual.encode(),
      );
      await expectLater(
        restarted.replaceRejected(actual, prepared(), attemptNumber: 1),
        failure(),
      );
      await expectLater(restarted.acknowledge(handle.operation), failure());
      platform.failDelete = true;
      await expectLater(restarted.acknowledge(actual), failure());
      expect(platform.values[actual.scope.storageKey], actual.encode());
      platform.failDelete = false;
      await restarted.acknowledge(actual);
      expect(platform.values, isEmpty);
    },
  );

  test(
    'timeout and retry rejection never erase the earlier unresolved attempt',
    () async {
      final first = await dispatch(await store.save(prepared()));
      final unknown = await store.recordAttemptOutcome(
        first,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.unresolved,
      );
      expect(unknown.revision, 2);
      final second = await dispatch(unknown);
      final actual = await reject(second);
      expect(actual.revision, 4);
      expect(actual.status, PendingOnboardingStatus.uncertain);
      expect(actual.attempts.map((a) => a.outcome), [
        OnboardingAttemptOutcome.unresolved,
        OnboardingAttemptOutcome.rejected,
      ]);
      await expectLater(reject(first), failure());
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 2),
        failure(),
      );
    },
  );

  test(
    'crash after dispatch preserves uncertainty across restart and retry',
    () async {
      final first = await dispatch(await store.save(prepared()));
      final restarted = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      final restored = (await restarted.read(first.operation.scope))!;
      await expectLater(
        restarted.recordAttemptOutcome(
          first,
          attemptNumber: 1,
          outcome: OnboardingAttemptOutcome.rejected,
          rejection: rejection,
        ),
        failure(),
      );
      final second = await restarted.markDispatched(
        restored,
        attemptNumber: 2,
        dispatchedAt: DateTime.utc(2026),
      );
      final actual = await restarted.recordAttemptOutcome(
        second,
        attemptNumber: 2,
        outcome: OnboardingAttemptOutcome.rejected,
        rejection: rejection,
      );
      expect(actual.status, PendingOnboardingStatus.uncertain);
      expect(actual.idempotencyKey, first.operation.idempotencyKey);
      expect(actual.request.frozenJson, first.operation.request.frozenJson);
      await expectLater(
        restarted.replaceRejected(actual, prepared(), attemptNumber: 2),
        failure(),
      );
    },
  );

  test(
    'fully rejected history can atomically replace in the same storage slot',
    () async {
      final first = await rejected();
      final second = await reject(await dispatch(first));
      expect(second.revision, 4);
      final corrected = prepared();
      final actual = await store.replaceRejected(
        second,
        corrected,
        attemptNumber: 2,
      );
      expect(actual.encode(), corrected.encode());
      expect(actual.idempotencyKey, isNot(second.idempotencyKey));
      expect(actual.status, PendingOnboardingStatus.prepared);
      expect(platform.values, {corrected.scope.storageKey: corrected.encode()});
      expect((await dispatch(actual)).attemptNumber, 1);
    },
  );

  test(
    'correction requires the exact revision, identity and final attempt number',
    () async {
      final actual = await rejected();
      final bytes = actual.encode();
      final stale = actual.withLedger(
        revision: 1,
        attempts: [
          OnboardingAttempt(
            number: 1,
            dispatchedAt: actual.attempts.single.dispatchedAt,
            outcome: OnboardingAttemptOutcome.unresolved,
          ),
        ],
      );
      for (final expected in [stale, prepared()]) {
        await expectLater(
          store.replaceRejected(expected, prepared(), attemptNumber: 1),
          failure(),
        );
      }
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 2),
        failure(),
      );
      expect(platform.values[actual.scope.storageKey], bytes);
    },
  );

  test(
    'correction blocks different gym, account, environment or API scope',
    () async {
      final actual = await rejected();
      final scopes = [
        onboardingScope(gymId: gymB),
        onboardingScope(userId: 'other-user'),
        onboardingScope(environment: AppEnvironment.production),
        onboardingScope(url: 'https://other.example.invalid/api/v1/'),
      ];
      for (final scope in scopes) {
        await expectLater(
          store.replaceRejected(
            actual,
            prepared(scope: scope),
            attemptNumber: 1,
          ),
          failure(OnboardingFailureKind.scopeMismatch),
        );
      }
      final misfiled = prepared(scope: onboardingScope(userId: 'other-user'));
      platform.values[actual.scope.storageKey] = misfiled.encode();
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 1),
        failure(OnboardingFailureKind.scopeMismatch),
      );
      expect(platform.values[actual.scope.storageKey], misfiled.encode());
    },
  );

  test(
    'correction blocks legacy records and keeps their exact bytes',
    () async {
      final operation = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      final json = jsonDecode(operation.encode()) as Map<String, dynamic>;
      final request = operation.request.toJson();
      request['membership']['payment']['paidAt'] =
          '2026-01-01T10:00:00.123456Z';
      json['requestJson'] = const JsonEncoder.withIndent('  ').convert(request);
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      json['idempotencyKey'] = 'Legacy_Stored-Key12345';
      final bytes = const JsonEncoder.withIndent('  ').convert(json);
      platform.values[operation.scope.storageKey] = bytes;
      final restored = (await store.read(operation.scope))!;
      await expectLater(
        store.replaceRejected(restored, prepared(), attemptNumber: 0),
        failure(),
      );
      await expectLater(dispatch(restored), failure());
      expect((await store.save(restored)).encode(), bytes);
      expect(platform.values[operation.scope.storageKey], bytes);
      expect(platform.writes, 0);
    },
  );

  test(
    'conflict remains blocked for correction, dispatch and acknowledgement',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      final actual = await store.recordAttemptOutcome(
        handle,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.conflict,
        rejection: conflict,
      );
      expect(actual.status, PendingOnboardingStatus.reconciliationRequired);
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 1),
        failure(),
      );
      await expectLater(dispatch(actual), failure());
      await expectLater(store.acknowledge(actual), failure());
      expect(platform.values[actual.scope.storageKey], actual.encode());
    },
  );

  test('prepared and active unresolved records cannot be corrected', () async {
    final actual = await store.save(prepared());
    await expectLater(
      store.replaceRejected(actual, prepared(), attemptNumber: 0),
      failure(),
    );
    final handle = await dispatch(actual);
    await expectLater(
      store.replaceRejected(handle.operation, prepared(), attemptNumber: 1),
      failure(),
    );
  });

  test('replacement must be fresh v2 prepared with a different key', () async {
    final actual = await rejected();
    final sameKey = jsonDecode(prepared().encode()) as Map<String, dynamic>;
    sameKey['idempotencyKey'] = actual.idempotencyKey;
    for (final replacement in [
      pendingOperation(),
      actual,
      PendingOnboardingOperation.decode(jsonEncode(sameKey)),
    ]) {
      await expectLater(
        store.replaceRejected(actual, replacement, attemptNumber: 1),
        failure(),
      );
    }
    expect(platform.values[actual.scope.storageKey], actual.encode());
  });

  for (final fault in [
    WriteFault.before,
    WriteFault.after,
    WriteFault.unreadable,
    WriteFault.dropped,
  ]) {
    test(
      'correction $fault reads back without deleting or regenerating keys',
      () async {
        final actual = await rejected();
        final replacement = prepared();
        platform.fault = fault;
        if (fault == WriteFault.after) {
          expect(
            (await store.replaceRejected(
              actual,
              replacement,
              attemptNumber: 1,
            )).encode(),
            replacement.encode(),
          );
        } else {
          await expectLater(
            store.replaceRejected(actual, replacement, attemptNumber: 1),
            failure(),
          );
        }
        platform.failRead = false;
        final current = (await store.read(actual.scope))!;
        expect(
          current.encode(),
          fault == WriteFault.before || fault == WriteFault.dropped
              ? actual.encode()
              : replacement.encode(),
        );
        expect(platform.values, hasLength(1));
        if (current.sameSubmission(replacement)) {
          expect(
            (await store.save(replacement)).idempotencyKey,
            replacement.idempotencyKey,
          );
          await expectLater(
            store.replaceRejected(actual, prepared(), attemptNumber: 1),
            failure(),
          );
        }
      },
    );
  }

  test(
    'concurrent corrections cannot overwrite the winning replacement',
    () async {
      final actual = await rejected();
      final first = prepared(), second = prepared();
      final winner = store.replaceRejected(actual, first, attemptNumber: 1);
      final loser = store.replaceRejected(actual, second, attemptNumber: 1);
      await expectLater(loser, failure());
      expect((await winner).encode(), first.encode());
      expect(platform.values[first.scope.storageKey], first.encode());
    },
  );

  test(
    'retry wins over stale correction and stale completed callback',
    () async {
      final initial = await store.save(prepared());
      final oldHandle = await dispatch(initial);
      final actual = await reject(oldHandle);
      final retry = dispatch(actual);
      final correction = store.replaceRejected(
        actual,
        prepared(),
        attemptNumber: 1,
      );
      await expectLater(correction, failure());
      final newHandle = await retry;
      await expectLater(reject(oldHandle), failure());
      expect(
        platform.values[actual.scope.storageKey],
        newHandle.operation.encode(),
      );
    },
  );

  test(
    'correction wins over stale retry without changing the new operation',
    () async {
      final actual = await rejected();
      final replacement = prepared();
      final correction = store.replaceRejected(
        actual,
        replacement,
        attemptNumber: 1,
      );
      final retry = dispatch(actual);
      await expectLater(retry, failure());
      expect((await correction).encode(), replacement.encode());
      expect(
        platform.values[replacement.scope.storageKey],
        replacement.encode(),
      );
    },
  );

  test('initial save cannot fabricate a v2 attempt ledger', () async {
    final operation = prepared();
    final seeded = operation.withLedger(
      revision: 2,
      attempts: [
        OnboardingAttempt(
          number: 1,
          dispatchedAt: DateTime.utc(2026),
          outcome: OnboardingAttemptOutcome.rejected,
          rejection: rejection,
        ),
      ],
    );
    await expectLater(store.save(seeded), failure());
    expect(platform.values, isEmpty);
  });

  test(
    'v2 updates retain the frozen body, key, timestamp and serialized scope',
    () async {
      final json = jsonDecode(prepared().encode()) as Map<String, dynamic>;
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      json['idempotencyKey'] = 'Existing_V2-Key123456';
      json['requestJson'] = const JsonEncoder.withIndent(
        '  ',
      ).convert(onboardingRequest().toJson());
      final operation = PendingOnboardingOperation.decode(jsonEncode(json));
      await store.save(operation);
      final actual = await reject(await dispatch(operation));
      final updated = jsonDecode(actual.encode()) as Map<String, dynamic>;
      for (final key in [
        'requestJson',
        'idempotencyKey',
        'createdAt',
        'scope',
      ]) {
        expect(updated[key], json[key]);
      }
    },
  );

  test(
    'legacy save and confirmation write-then-throw verify existing slot',
    () async {
      final operation = pendingOperation();
      platform.fault = WriteFault.after;
      expect((await store.save(operation)).encode(), operation.encode());
      platform.fault = WriteFault.after;
      await store.confirm(operation, resultFor(operation));
      expect(
        (await store.read(operation.scope))!.status,
        PendingOnboardingStatus.confirmed,
      );
    },
  );

  test(
    'missing rejection evidence cannot be persisted as non-commit',
    () async {
      final handle = await dispatch(await store.save(prepared()));
      await expectLater(
        store.recordAttemptOutcome(
          handle,
          attemptNumber: 1,
          outcome: OnboardingAttemptOutcome.rejected,
        ),
        failure(OnboardingFailureKind.validation),
      );
      expect(
        (await store.read(handle.operation.scope))!.attempts.single.rejection,
        isNull,
      );
    },
  );

  test(
    'saved marker after thrown write stays unresolved even after retry rejection',
    () async {
      final operation = await store.save(prepared());
      platform.fault = WriteFault.after;
      await expectLater(dispatch(operation), failure());
      final marked = (await store.read(operation.scope))!;
      final actual = await reject(await dispatch(marked));
      expect(
        actual.attempts.first.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
      expect(actual.status, PendingOnboardingStatus.uncertain);
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 2),
        failure(),
      );
    },
  );

  test(
    'retry success can confirm without rewriting older unresolved history',
    () async {
      final first = await dispatch(await store.save(prepared()));
      final unknown = await store.recordAttemptOutcome(
        first,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.unresolved,
      );
      final second = await dispatch(unknown);
      final actual = await store.recordAttemptOutcome(
        second,
        attemptNumber: 2,
        outcome: OnboardingAttemptOutcome.confirmed,
        result: resultFor(second.operation),
      );
      expect(
        actual.attempts.first.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
      expect(actual.status, PendingOnboardingStatus.confirmed);
      await expectLater(
        store.replaceRejected(actual, prepared(), attemptNumber: 2),
        failure(),
      );
      await expectLater(reject(first), failure());
      await store.acknowledge(actual);
      expect(platform.values, isEmpty);
    },
  );

  test(
    'correction can save a changed body only with a new prepared identity',
    () async {
      final old = await rejected();
      final body = old.request.toJson();
      body['member']['memberCode'] = 'ME02';
      final corrected = PendingOnboardingOperation.prepared(
        scope: old.scope,
        request: OnboardingRequest.fromFrozenJson(jsonEncode(body)),
      );
      final actual = await store.replaceRejected(
        old,
        corrected,
        attemptNumber: 1,
      );
      expect(actual.request.frozenJson, corrected.request.frozenJson);
      expect(actual.request.frozenJson, isNot(old.request.frozenJson));
      expect(actual.idempotencyKey, corrected.idempotencyKey);
    },
  );

  test(
    'independent scopes can hold live dispatches without overwriting one another',
    () async {
      final first = await dispatch(await store.save(prepared()));
      final other = prepared(scope: onboardingScope(userId: 'other-user'));
      final second = await dispatch(await store.save(other));
      final outcomes = await Future.wait([reject(first), reject(second)]);
      expect(
        outcomes.every((o) => o.status == PendingOnboardingStatus.rejected),
        isTrue,
      );
      expect(platform.values, hasLength(2));
      expect(
        platform.values[first.operation.scope.storageKey],
        outcomes.first.encode(),
      );
      expect(
        platform.values[second.operation.scope.storageKey],
        outcomes.last.encode(),
      );
    },
  );

  test('legacy model cannot be updated with invented attempt history', () {
    final old = pendingOperation();
    expect(
      () => old.withLedger(revision: 0, attempts: []),
      failure(OnboardingFailureKind.unsupportedVersion),
    );
    expect(old.version, 1);
    expect(old.attempts, isEmpty);
  });
}
