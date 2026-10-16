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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestOnboardingStorage platform;
  late SecurePendingOnboardingStore store;
  setUp(() {
    platform = TestOnboardingStorage();
    store = SecurePendingOnboardingStore(
      storage: platform,
      queue: OnboardingOperationQueue(),
    );
  });
  test(
    'actual platform adapter stores only its exact scoped key and frozen versioned record',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'unrelated.refresh': 'synthetic-not-a-credential',
      });
      const native = FlutterSecureStorage();
      final adapter = SecurePendingOnboardingStore(
        storage: native,
        queue: OnboardingOperationQueue(),
      );
      final operation = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      await adapter.save(operation);
      final keys = await native.readAll();
      expect(keys.keys.toSet(), {
        'unrelated.refresh',
        operation.scope.storageKey,
      });
      expect(
        operation.scope.storageKey,
        'gym.onboarding.v1.development.'
        '${Uri.encodeComponent(onboardingUrl)}.test-account.$gymA.pending',
      );
      final encoded = jsonDecode(keys[operation.scope.storageKey]!) as Map;
      expect(encoded['version'], 1);
      expect(encoded['status'], 'pending');
      expect(encoded['requestJson'], operation.request.frozenJson);
      final restored = await adapter.read(operation.scope);
      expect(restored!.sameSubmission(operation), isTrue);
      final result = OnboardingResult.fromJson(
        onboardingResultJson(operation.request),
      );
      await adapter.confirm(operation, result);
      await adapter.acknowledge(operation);
      expect(await native.readAll(), {
        'unrelated.refresh': 'synthetic-not-a-credential',
      });
    },
  );
  test('environment, URL, user and gym scopes have isolated records', () async {
    final scopes = [
      onboardingScope(),
      onboardingScope(environment: AppEnvironment.production),
      onboardingScope(url: 'https://other.example.invalid/api/v1/'),
      onboardingScope(userId: 'another-test-user'),
      onboardingScope(gymId: gymB),
    ];
    expect(scopes.map((s) => s.storageKey).toSet(), hasLength(scopes.length));
    for (final scope in scopes) {
      await store.save(pendingOperation(scope: scope));
    }
    for (final scope in scopes) {
      final saved = await store.read(scope);
      expect(saved!.scope.matches(scope), isTrue);
    }
    expect(platform.values, hasLength(5));
  });
  test(
    'legacy reads and blocked replacements leave the original bytes untouched',
    () async {
      final operation = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      final body = operation.request.toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final json = jsonDecode(operation.encode()) as Map<String, dynamic>;
      json['requestJson'] = const JsonEncoder.withIndent('  ').convert(body);
      json['idempotencyKey'] = 'Legacy_Stored-Key12345';
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      final encoded = const JsonEncoder.withIndent('  ').convert(json);
      platform.values[operation.scope.storageKey] = encoded;
      final restored = (await store.read(operation.scope))!;
      expect(restored.encode(), encoded);
      expect(restored.version, 1);
      expect((await store.save(restored)).encode(), encoded);
      await expectLater(
        store.save(pendingOperation()),
        throwsA(isA<OnboardingFailure>()),
      );
      await expectLater(
        store.acknowledge(restored),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(platform.writes, 0);
      expect(platform.values, {operation.scope.storageKey: encoded});
    },
  );
  for (final status in [
    'prepared',
    'rejected',
    'uncertain',
    'reconciliationRequired',
  ]) {
    test(
      'v2 $status is decoded in the existing slot without rewriting or releasing it',
      () async {
        final operation = pendingOperation();
        final json = jsonDecode(operation.encode()) as Map<String, dynamic>;
        json['version'] = 2;
        json['status'] = status;
        json['revision'] = status == 'prepared'
            ? 0
            : status == 'uncertain'
            ? 1
            : 2;
        json['attempts'] = status == 'prepared'
            ? []
            : [
                {
                  'number': 1,
                  'dispatchedAt': '2026-01-01T10:00:00Z',
                  'outcome': status == 'uncertain'
                      ? 'unresolved'
                      : status == 'rejected'
                      ? 'rejected'
                      : 'conflict',
                  if (status == 'rejected' ||
                      status == 'reconciliationRequired')
                    'rejection': {
                      'type': 'backendRejection',
                      'code': status == 'rejected'
                          ? 'PLAN_NOT_FOUND'
                          : 'IDEMPOTENCY_KEY_CONFLICT',
                      'status': status == 'rejected' ? 404 : 409,
                    },
                },
              ];
        final encoded = jsonEncode(json);
        platform.values[operation.scope.storageKey] = encoded;
        final restored = (await store.read(operation.scope))!;
        expect(restored.version, 2);
        expect(restored.status.name, status);
        expect(restored.scope.storageKey, operation.scope.storageKey);
        expect(restored.encode(), encoded);
        await expectLater(
          store.save(pendingOperation()),
          throwsA(isA<OnboardingFailure>()),
        );
        await expectLater(
          store.acknowledge(restored),
          throwsA(isA<OnboardingFailure>()),
        );
        expect(platform.writes, 0);
        expect(platform.values, {operation.scope.storageKey: encoded});
      },
    );
  }
  test('malformed v2 records are retained rather than overwritten', () async {
    final operation = pendingOperation();
    final json = jsonDecode(operation.encode()) as Map<String, dynamic>;
    json.addAll({
      'version': 2,
      'status': 'rejected',
      'revision': 0,
      'attempts': [],
    });
    final encoded = jsonEncode(json);
    platform.values[operation.scope.storageKey] = encoded;
    for (final action in [
      () => store.read(operation.scope),
      () => store.save(pendingOperation()),
    ]) {
      await expectLater(
        action(),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.kind,
            'kind',
            OnboardingFailureKind.corruptRecord,
          ),
        ),
      );
    }
    expect(platform.writes, 0);
    expect(platform.values[operation.scope.storageKey], encoded);
  });
  test(
    'mismatched record in current key is retained but never returned',
    () async {
      final scope = onboardingScope();
      platform.values[scope.storageKey] = pendingOperation(
        scope: onboardingScope(gymId: gymB),
      ).encode();
      await expectLater(
        store.read(scope),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.kind,
            'kind',
            OnboardingFailureKind.scopeMismatch,
          ),
        ),
      );
      expect(platform.values, hasLength(1));
      expect(platform.writes, 0);
    },
  );
  for (final encoded in [
    'not json',
    '{}',
    '{"version":1,"status":"invalid"}',
  ]) {
    test('corrupt record is retained: $encoded', () async {
      final scope = onboardingScope();
      platform.values[scope.storageKey] = encoded;
      await expectLater(
        store.read(scope),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.kind,
            'kind',
            OnboardingFailureKind.corruptRecord,
          ),
        ),
      );
      await expectLater(
        store.save(pendingOperation()),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(platform.values[scope.storageKey], encoded);
    });
  }
  test(
    'unsupported version remains distinguishable and is not overwritten',
    () async {
      final scope = onboardingScope();
      final encoded = jsonEncode({
        ...jsonDecode(pendingOperation().encode()) as Map,
        'version': 999,
      });
      platform.values[scope.storageKey] = encoded;
      await expectLater(
        store.read(scope),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.kind,
            'kind',
            OnboardingFailureKind.unsupportedVersion,
          ),
        ),
      );
      expect(platform.values[scope.storageKey], encoded);
    },
  );
  test(
    'persisted unknown secrets or malformed status are corrupt, never silently sanitized',
    () {
      final base =
          jsonDecode(pendingOperation().encode()) as Map<String, dynamic>;
      for (final invalid in [
        {...base, 'password': 'not-a-password'},
        {...base, 'status': 'confirmed'},
      ]) {
        expect(
          () => PendingOnboardingOperation.decode(jsonEncode(invalid)),
          throwsA(
            isA<OnboardingFailure>().having(
              (e) => e.kind,
              'kind',
              OnboardingFailureKind.corruptRecord,
            ),
          ),
        );
      }
    },
  );
  test('read/write storage failures have safe typed errors', () async {
    platform.failRead = true;
    await expectLater(
      store.read(onboardingScope()),
      throwsA(
        isA<OnboardingFailure>().having(
          (e) => e.kind,
          'kind',
          OnboardingFailureKind.localStorage,
        ),
      ),
    );
    platform.failRead = false;
    platform.failWrite = true;
    await expectLater(
      store.save(pendingOperation()),
      throwsA(
        isA<OnboardingFailure>().having(
          (e) => e.kind,
          'kind',
          OnboardingFailureKind.localStorage,
        ),
      ),
    );
    expect(platform.values, isEmpty);
  });
  test('unresolved operation cannot be replaced or acknowledged', () async {
    final operation = pendingOperation();
    await store.save(operation);
    await expectLater(
      store.save(pendingOperation()),
      throwsA(
        isA<OnboardingFailure>().having(
          (e) => e.kind,
          'kind',
          OnboardingFailureKind.pendingOperation,
        ),
      ),
    );
    await expectLater(
      store.acknowledge(operation),
      throwsA(isA<OnboardingFailure>()),
    );
    expect(
      (await store.read(operation.scope))!.sameSubmission(operation),
      isTrue,
    );
  });
  test(
    'concurrent save calls cannot overwrite one another and queue survives failure',
    () async {
      final operations = [pendingOperation(), pendingOperation()];
      final first = store.save(operations.first);
      final second = store.save(operations.last);
      await expectLater(second, throwsA(isA<OnboardingFailure>()));
      await first;
      expect(
        (await store.read(
          operations.first.scope,
        ))!.sameSubmission(operations.first),
        isTrue,
      );
    },
  );
  test(
    'confirmation survives reconstruction and cannot be downgraded by stale save',
    () async {
      final operation = pendingOperation();
      await store.save(operation);
      await store.confirm(
        operation,
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      final reconstructed = SecurePendingOnboardingStore(
        storage: platform,
        queue: OnboardingOperationQueue(),
      );
      expect(
        (await reconstructed.read(operation.scope))!.status,
        PendingOnboardingStatus.confirmed,
      );
      expect(
        (await reconstructed.save(operation)).result!.operationId,
        onboardingOperationId,
      );
    },
  );
  test(
    'failed confirmation retains original pending data; failed acknowledgement retains confirmation',
    () async {
      final operation = pendingOperation();
      await store.save(operation);
      platform.failWrite = true;
      final result = OnboardingResult.fromJson(
        onboardingResultJson(operation.request),
      );
      await expectLater(
        store.confirm(operation, result),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(
        (await store.read(operation.scope))!.status,
        PendingOnboardingStatus.pending,
      );
      platform.failWrite = false;
      await store.confirm(operation, result);
      platform.failDelete = true;
      await expectLater(
        store.acknowledge(operation),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(
        (await store.read(operation.scope))!.status,
        PendingOnboardingStatus.confirmed,
      );
    },
  );

  test(
    'acknowledgement guard failure preserves the exact confirmed record',
    () async {
      final operation = pendingOperation();
      final confirmed = operation.confirmed(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      platform.values[operation.scope.storageKey] = confirmed.encode();
      var checked = false;
      await expectLater(
        store.acknowledge(
          confirmed,
          beforePersist: () {
            checked = true;
            throw const OnboardingFailure(OnboardingFailureKind.scopeMismatch);
          },
        ),
        throwsA(
          isA<OnboardingFailure>().having(
            (failure) => failure.kind,
            'kind',
            OnboardingFailureKind.scopeMismatch,
          ),
        ),
      );
      expect(checked, isTrue);
      expect(platform.values, {operation.scope.storageKey: confirmed.encode()});
      await store.acknowledge(confirmed);
      expect(platform.values, isEmpty);
    },
  );

  test(
    'stale acknowledgement cannot clear a newer confirmed identity',
    () async {
      final stale = pendingOperation();
      final newer = pendingOperation();
      final confirmed = newer.confirmed(
        OnboardingResult.fromJson(onboardingResultJson(newer.request)),
      );
      platform.values[newer.scope.storageKey] = confirmed.encode();
      var checked = false;
      await expectLater(
        store.acknowledge(stale, beforePersist: () => checked = true),
        throwsA(
          isA<OnboardingFailure>().having(
            (failure) => failure.kind,
            'kind',
            OnboardingFailureKind.pendingOperation,
          ),
        ),
      );
      expect(checked, isFalse);
      expect(platform.values, {newer.scope.storageKey: confirmed.encode()});
    },
  );

  test(
    'acknowledgement rejects a foreign scope stored in the expected slot',
    () async {
      final expected = pendingOperation();
      final foreign = pendingOperation(scope: onboardingScope(gymId: gymB));
      final confirmed = foreign.confirmed(
        OnboardingResult.fromJson(
          onboardingResultJson(foreign.request, gymId: gymB),
        ),
      );
      platform.values[expected.scope.storageKey] = confirmed.encode();
      var checked = false;
      await expectLater(
        store.acknowledge(expected, beforePersist: () => checked = true),
        throwsA(
          isA<OnboardingFailure>().having(
            (failure) => failure.kind,
            'kind',
            OnboardingFailureKind.scopeMismatch,
          ),
        ),
      );
      expect(checked, isFalse);
      expect(platform.values, {expected.scope.storageKey: confirmed.encode()});
    },
  );
}
