import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_service.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/onboarding_secure_storage.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';

import 'onboarding_fakes.dart';

// Models the *native contract*, not a proof about Android disk or Keychain.
// Cache survives method calls; only disk survives process reconstruction.
class NativePersistenceFake {
  final cache = <String, String>{};
  final disk = <String, String>{};
  final calls = <MethodCall>[];
  int writes = 0;
  int unchangedShortcuts = 0;
  bool diskFileExists = false;

  // API 24 processes clear before puts. An unchanged editor with an existing
  // file returns true without attempting disk IO, even after an earlier failure.
  bool commitSnapshot(
    Map<String, String> snapshot, {
    required bool clear,
    bool fail = false,
  }) {
    var changed = clear && cache.isNotEmpty;
    if (clear) cache.clear();
    for (final entry in snapshot.entries) {
      if (cache[entry.key] != entry.value) {
        cache[entry.key] = entry.value;
        changed = true;
      }
    }
    if ((diskFileExists || disk.isNotEmpty) && !changed) {
      unchangedShortcuts++;
      return true;
    }
    if (fail) return false;
    diskFileExists = true;
    disk
      ..clear()
      ..addAll(cache);
    return true;
  }

  bool oldUnchangedVerification() =>
      commitSnapshot(Map.of(cache), clear: false, fail: true);
  int? failWrite, throwAfterWrite;
  bool failBarrier = false, failMarkerVerification = false;
  Completer<void>? markerGate, markerEntered;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = call.arguments as Map;
    final key = args['key'] as String;
    switch (call.method) {
      case 'writeOnboarding':
        writes++;
        final snapshot = Map<String, String>.of(cache);
        snapshot[key] = args['value'] as String;
        if (writes == 2 && markerGate != null) {
          markerEntered!.complete();
          await markerGate!.future;
        }
        if (!commitSnapshot(snapshot, clear: true, fail: writes == failWrite)) {
          failBarrier = true;
          throw PlatformException(code: 'unverified_commit');
        }
        if (writes == 2 && failMarkerVerification) failBarrier = true;
        if (writes == throwAfterWrite) {
          throw PlatformException(code: 'committed_then_channel_error');
        }
        return disk[key];
      case 'readOnboarding':
        if (!commitSnapshot(Map.of(cache), clear: true, fail: failBarrier)) {
          throw PlatformException(code: 'unverified_barrier');
        }
        return cache[key];
      case 'deleteOnboarding':
        if (failBarrier) throw PlatformException(code: 'unverified_commit');
        cache.remove(key);
        disk.remove(key);
        return null;
      default:
        throw StateError('Onboarding used ordinary storage: ${call.method}');
    }
  }

  void restart() {
    cache.clear();
    cache.addAll(disk);
    failBarrier = false;
    failWrite = null;
    throwAfterWrite = null;
    failMarkerVerification = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const native = OnboardingSecureStorage();
  late NativePersistenceFake platform;
  late SecurePendingOnboardingStore store;
  late FakeOnboardingRepository repository;
  late MemberOnboardingService service;

  void reconstruct() {
    store = SecurePendingOnboardingStore(
      storage: native,
      queue: OnboardingOperationQueue(),
    );
    service = MemberOnboardingService(
      repository: repository,
      store: store,
      queue: OnboardingOperationQueue(),
      isAuthorized: (_) => true,
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = NativePersistenceFake();
    repository = FakeOnboardingRepository();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, platform.handle);
    reconstruct();
  });
  tearDown(() {
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  PendingOnboardingOperation operation() => PendingOnboardingOperation.prepared(
    scope: onboardingScope(),
    request: onboardingRequest(membership: true, amount: 40000),
  );
  final fails = throwsA(isA<OnboardingFailure>());

  test(
    'API 24 simulator exposes unchanged false success after failed write',
    () {
      platform.diskFileExists = true;
      platform.disk['record'] = 'unconfirmed';
      platform.cache.addAll(platform.disk);
      expect(
        platform.commitSnapshot(
          {'record': 'confirmed'},
          clear: false,
          fail: true,
        ),
        isFalse,
      );
      expect(platform.oldUnchangedVerification(), isTrue);
      expect(platform.cache['record'], 'confirmed');
      expect(platform.disk['record'], 'unconfirmed');
      expect(
        platform.commitSnapshot(
          Map.of(platform.cache),
          clear: true,
          fail: true,
        ),
        isFalse,
      );
      platform.restart();
      expect(platform.cache['record'], 'unconfirmed');
    },
  );

  test(
    'only opt-in methods receive exact key, value and original options',
    () async {
      final pending = operation();
      await store.save(pending);
      final write = platform.calls.singleWhere(
        (c) => c.method == 'writeOnboarding',
      );
      final args = write.arguments as Map;
      expect(args['key'], pending.scope.storageKey);
      expect(args['value'], pending.encode());
      expect((args['options'] as Map)['resetOnError'], 'false');
      expect(platform.disk, {pending.scope.storageKey: pending.encode()});
      expect((await store.read(pending.scope))!.encode(), pending.encode());
    },
  );

  test(
    'iOS keeps original service, accessibility and non-enclave format',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await store.save(operation());
      final options = (platform.calls.first.arguments as Map)['options'] as Map;
      expect(options['accountName'], 'flutter_secure_storage_service');
      expect(options['accessibility'], 'unlocked_this_device');
      expect(options['synchronizable'], 'false');
      expect(options['useSecureEnclave'], 'false');
    },
  );

  test(
    'unsupported platform cannot silently fall back to ordinary writes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await expectLater(store.save(operation()), fails);
      expect(platform.calls, isEmpty);
    },
  );

  test('auth keys and null writes cannot enter the onboarding path', () async {
    await expectLater(
      Future.sync(() => native.read(key: 'auth.refresh')),
      throwsArgumentError,
    );
    await expectLater(
      native.write(key: operation().scope.storageKey, value: null),
      throwsArgumentError,
    );
    expect(platform.calls, isEmpty);
  });

  test('network waits for marker native commit and verification', () async {
    final pending = operation();
    platform.markerGate = Completer<void>();
    platform.markerEntered = Completer<void>();
    final submitted = service.submit(pending);
    await platform.markerEntered!.future;
    expect(repository.calls, isEmpty);
    final disk = PendingOnboardingOperation.decode(
      platform.disk[pending.scope.storageKey]!,
    );
    expect(disk.status, PendingOnboardingStatus.prepared);
    platform.markerGate!.complete();
    await submitted;
    expect(repository.calls, hasLength(1));
    final saved = (await store.read(pending.scope))!;
    expect(saved.result, isNotNull);
  });

  test(
    'failed marker commit with matching cache cannot dispatch; disk survives restart',
    () async {
      final pending = operation();
      platform.failWrite = 2;
      await expectLater(service.submit(pending), fails);
      expect(repository.calls, isEmpty);
      expect(
        PendingOnboardingOperation.decode(
          platform.cache[pending.scope.storageKey]!,
        ).attempts,
        hasLength(1),
      );
      expect(
        PendingOnboardingOperation.decode(
          platform.disk[pending.scope.storageKey]!,
        ).attempts,
        isEmpty,
      );
      service.dispose();
      platform.restart();
      reconstruct();
      final restored = (await service.restore(pending.scope))!;
      expect(restored.request.frozenJson, pending.request.frozenJson);
      expect(restored.idempotencyKey, pending.idempotencyKey);
      await service.recover(pending.scope);
      expect(repository.calls.map((c) => c.key).toList(), [
        pending.idempotencyKey,
      ]);
      expect(repository.calls.single.body, pending.request.frozenJson);
    },
  );

  test(
    'successful marker commit but failed verification cannot dispatch',
    () async {
      final pending = operation();
      platform.failMarkerVerification = true;
      await expectLater(service.submit(pending), fails);
      expect(repository.calls, isEmpty);
      expect(
        PendingOnboardingOperation.decode(
          platform.disk[pending.scope.storageKey]!,
        ).attempts,
        hasLength(1),
      );
      service.dispose();
      platform.restart();
      reconstruct();
      await service.recover(pending.scope);
      expect(repository.calls.map((c) => c.key).toList(), [
        pending.idempotencyKey,
      ]);
      expect((await store.read(pending.scope))!.attempts, hasLength(2));
    },
  );

  test(
    'commit-then-throw marker remains withheld even after a successful barrier',
    () async {
      final pending = operation();
      platform.throwAfterWrite = 2;
      await expectLater(service.submit(pending), fails);
      expect(repository.calls, isEmpty);
      expect((await store.read(pending.scope))!.attempts, hasLength(1));
    },
  );

  test(
    'failed confirmation cannot expose cached success; restart replays exact operation',
    () async {
      final pending = operation();
      platform.failWrite = 3;
      await expectLater(service.submit(pending), fails);
      expect(repository.calls, hasLength(1));
      expect(
        PendingOnboardingOperation.decode(
          platform.cache[pending.scope.storageKey]!,
        ).result,
        isNotNull,
      );
      expect(
        PendingOnboardingOperation.decode(
          platform.disk[pending.scope.storageKey]!,
        ).result,
        isNull,
      );
      // The old native snapshot re-put would return true while disk remained
      // unconfirmed. The fixed clear+reinsertion barrier must still refuse it.
      expect(platform.oldUnchangedVerification(), isTrue);
      expect(platform.unchangedShortcuts, greaterThan(0));
      expect(
        PendingOnboardingOperation.decode(
          platform.disk[pending.scope.storageKey]!,
        ).result,
        isNull,
      );
      await expectLater(service.restore(pending.scope), fails);
      service.dispose();
      platform.restart();
      reconstruct();
      final result = await service.recover(pending.scope);
      expect(result.member.id, isNotEmpty);
      expect(repository.calls.map((c) => c.key).toList(), [
        pending.idempotencyKey,
        pending.idempotencyKey,
      ]);
      expect(
        repository.calls.map((c) => c.body),
        everyElement(pending.request.frozenJson),
      );
      expect(
        (await store.read(pending.scope))!.attempts.first.outcome,
        OnboardingAttemptOutcome.unresolved,
      );
    },
  );

  test(
    'commit-then-throw confirmation requires a successful native barrier',
    () async {
      final pending = operation();
      platform.throwAfterWrite = 3;
      await service.submit(pending);
      expect((await store.read(pending.scope))!.result, isNotNull);
      service.dispose();
      platform.restart();
      reconstruct();
      await service.recover(pending.scope);
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'failed correction preserves durable original; retry uses same replacement',
    () async {
      final pending = operation();
      await store.save(pending);
      final handle = await store.markDispatched(
        pending,
        attemptNumber: 1,
        dispatchedAt: DateTime.utc(2026),
      );
      final rejected = await store.recordAttemptOutcome(
        handle,
        attemptNumber: 1,
        outcome: OnboardingAttemptOutcome.rejected,
        rejection: OnboardingBackendRejection.tryFrom(
          'DUPLICATE_MEMBER_CODE',
          409,
        ),
      );
      final replacement = operation();
      platform.failWrite = 4;
      await expectLater(service.correct(rejected, replacement), fails);
      expect(platform.disk[pending.scope.storageKey], rejected.encode());
      service.dispose();
      platform.restart();
      reconstruct();
      expect(
        (await service.restore(pending.scope))!.idempotencyKey,
        pending.idempotencyKey,
      );
      await service.correct(rejected, replacement);
      expect(
        (await service.restore(pending.scope))!.encode(),
        replacement.encode(),
      );
      expect(repository.calls, isEmpty);
    },
  );

  test(
    'legacy encoding, microseconds and key survive native read and restart unchanged',
    () async {
      final pending = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      final json = jsonDecode(pending.encode()) as Map<String, dynamic>;
      final body = pending.request.toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      json['requestJson'] = const JsonEncoder.withIndent('  ').convert(body);
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      json['idempotencyKey'] = 'Legacy_Stored-Key12345';
      final encoded = const JsonEncoder.withIndent('  ').convert(json);
      platform.disk[pending.scope.storageKey] = encoded;
      platform.restart();
      expect((await service.restore(pending.scope))!.encode(), encoded);
      expect(platform.writes, 0);
      expect(platform.disk[pending.scope.storageKey], encoded);
      await service.recover(pending.scope);
      expect(repository.calls.map((c) => c.key).toList(), [
        'Legacy_Stored-Key12345',
      ]);
      expect(repository.calls.single.body, json['requestJson']);
      expect((await service.restore(pending.scope))!.version, 1);
    },
  );

  test(
    'explicit acknowledgement deletes only the confirmed scoped record',
    () async {
      final pending = operation();
      platform.disk['unrelated.refresh'] = 'synthetic';
      platform.cache.addAll(platform.disk);
      await service.submit(pending);
      await service.acknowledge((await service.restore(pending.scope))!);
      expect(platform.disk, {'unrelated.refresh': 'synthetic'});
      expect(platform.calls.last.method, 'deleteOnboarding');
    },
  );
}
