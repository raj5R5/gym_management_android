import 'dart:async';
import 'package:dio/dio.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/data/payment_repository.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';

import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import '../members/member_fakes.dart';
import '../members/onboarding_fakes.dart' show onboardingUrl;
import 'payment_fakes.dart';

// This simulates the durable adapter contract, not Android disk or iOS Keychain.
// A failed write can change cache; only disk survives reconstruction.
class RecoveryDisk extends FlutterSecureStorage {
  RecoveryDisk([Map<String, String>? disk]) : disk = disk ?? {};
  final Map<String, String> disk;
  final cache = <String, String>{};
  final writes = <String>[];
  bool failRead = false, failDelete = false;
  int? failWrite, throwAfterWrite, gateWrite;
  Completer<void>? gate, entered, readGate, readEntered;
  RecoveryDisk restart() => RecoveryDisk(disk);
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (readEntered != null && !readEntered!.isCompleted) {
      readEntered!.complete();
    }
    if (readGate != null) await readGate!.future;
    if (failRead) throw StateError('Synthetic durable read failure');
    return disk[key];
  }

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
  }) async {
    writes.add(value!);
    cache[key] = value;
    if (writes.length == gateWrite) {
      entered!.complete();
      await gate!.future;
    }
    if (writes.length == failWrite) {
      throw StateError('Synthetic commit failure');
    }
    disk[key] = value;
    if (writes.length == throwAfterWrite) {
      throw StateError('Synthetic lost storage acknowledgement');
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (failDelete) throw StateError('Synthetic delete failure');
    disk.remove(key);
  }
}

class ReplayPayments extends FakePaymentRepository {
  final committed = <String, ({String body, RecordedPayment receipt})>{};
  bool loseResponse = false;
  int inserts = 0;
  void Function(PaymentCollection)? beforeRecord;
  @override
  Future<RecordedPayment> record(
    String gymId,
    PaymentCollection collection, {
    CancelToken? cancelToken,
  }) async {
    beforeRecord?.call(collection);
    collections.add(collection);
    cancellationTokens.add(cancelToken);
    final existing = committed[collection.key];
    if (existing != null) {
      if (existing.body != collection.frozenJson) {
        throw const BillingFailure(
          'Key conflict',
          uncertain: true,
          code: 'IDEMPOTENCY_KEY_CONFLICT',
          httpStatus: 409,
        );
      }
      return existing.receipt;
    }
    if (failure != null) throw failure!;
    if (gate != null) await gate!.future;
    final receipt = confirmation(collection);
    committed[collection.key] = (body: collection.frozenJson, receipt: receipt);
    inserts++;
    if (loseResponse) {
      throw const BillingFailure('Response lost after commit', uncertain: true);
    }
    return receipt;
  }
}

class RecoveryConfig extends Notifier<AppConfig> {
  @override
  AppConfig build() => AppConfig.fromValues(apiBaseUrl: onboardingUrl);
  void change(String url) => state = AppConfig.fromValues(apiBaseUrl: url);
}

final recoveryConfigProvider = NotifierProvider<RecoveryConfig, AppConfig>(
  RecoveryConfig.new,
);

void main() {
  late RecoveryDisk storage;
  late ReplayPayments repository;
  late ProviderContainer container;
  var generatedKeys = 0;
  final scope = (
    member: (userId: 'test-account', gymId: gymA, memberId: memberId),
    subscriptionId: subscriptionId,
  );
  final config = AppConfig.fromValues(apiBaseUrl: onboardingUrl);
  final recoveryScope = PaymentRecoveryScope.fromConfig(
    config,
    userId: 'test-account',
    gymId: gymA,
    memberId: memberId,
    subscriptionId: subscriptionId,
  );
  ManualPayment payment([int amount = 50003]) => ManualPayment(
    amountPaise: amount,
    method: PaymentMethod.upi,
    reference: 'TEST-REF',
    paidAt: DateTime.utc(2026, 1, 1, 10, 0, 0, 123, 456),
  );
  PendingPayment frozen() => PendingPayment(
    scope: recoveryScope,
    createdAt: DateTime.utc(2026),
    collection: PaymentCollection(
      memberId: memberId,
      subscriptionId: subscriptionId,
      key: 'original-test-key',
      payment: payment(),
    ),
  );
  Future<ProviderContainer> start({AuthIdentity? identity}) async {
    final next = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) => ref.watch(recoveryConfigProvider),
        ),
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()
            ..identity = identity ?? adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        paymentRepositoryProvider.overrideWithValue(repository),
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: storage,
            queue: OnboardingOperationQueue(),
          ),
        ),
        paymentKeyFactoryProvider.overrideWithValue(
          () => 'new-payment-key-${++generatedKeys}',
        ),
      ],
    );
    await next
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
    return next;
  }

  Future<void> restart() async {
    container.dispose();
    storage = storage.restart();
    container = await start();
  }

  PaymentCollectionController controller() =>
      container.read(paymentCollectionProvider(scope).notifier);
  PendingPayment saved() =>
      PendingPayment.decode(storage.disk[recoveryScope.storageKey]!);
  setUp(() async {
    storage = RecoveryDisk();
    repository = ReplayPayments();
    generatedKeys = 0;
    container = await start();
  });
  tearDown(() => container.dispose());

  test(
    'prepared request and verified dispatch marker precede repository call',
    () async {
      repository.beforeRecord = (collection) {
        final durable = saved();
        expect(storage.writes, hasLength(2));
        expect(
          durable.attempts.single.outcome,
          PaymentAttemptOutcome.unresolved,
        );
        expect(durable.collection.frozenJson, collection.frozenJson);
        expect(durable.collection.key, collection.key);
      };
      expect(await controller().collect(payment(), 100000), isNotNull);
      expect(saved().result, isNotNull);
      expect(saved().collection.body['paidAt'], '2026-01-01T10:00:00.123Z');
    },
  );

  for (final failedWrite in [1, 2]) {
    test(
      'write $failedWrite failure cannot send even when cache matches',
      () async {
        storage.failWrite = failedWrite;
        await controller().collect(payment(), 100000);
        expect(repository.collections, isEmpty);
        expect(storage.cache.values.single, isNotNull);
        final original = PendingPayment.decode(storage.writes.first);
        storage.failWrite = null;
        await controller().retrySaved();
        expect(repository.collections, hasLength(1));
        expect(repository.collections.single.key, original.collection.key);
        expect(
          repository.collections.single.frozenJson,
          original.collection.frozenJson,
        );
        expect(generatedKeys, 1);
      },
    );
  }

  test(
    'prepared operation restored after restart sends its exact request/key',
    () async {
      final original = frozen();
      storage.disk[recoveryScope.storageKey] = original.encode();
      await restart();
      expect(
        await container.read(paymentCollectionProvider(scope).future),
        isNull,
      );
      expect(controller().blocked, isTrue);
      expect(repository.collections, isEmpty);
      expect(await controller().collect(payment(10000), 100000), isNull);
      await controller().retrySaved();
      expect(repository.collections.single.key, original.collection.key);
      expect(
        repository.collections.single.frozenJson,
        original.collection.frozenJson,
      );
      expect(generatedKeys, 0);
    },
  );

  test(
    'committed response lost then process restart replays one immutable receipt',
    () async {
      repository.loseResponse = true;
      expect(await controller().collect(payment(), 100000), isNull);
      final original = saved();
      expect(repository.inserts, 1);
      await restart();
      await container.read(paymentCollectionProvider(scope).future);
      expect(controller().blocked, isTrue);
      expect(
        controller().savedCollection!.body['transactionReference'],
        'TEST-REF',
      );
      expect(await controller().collect(payment(10000), 100000), isNull);
      repository.loseResponse = false;
      expect(
        (await controller().retrySaved())!.id,
        repository.committed.values.single.receipt.id,
      );
      expect(repository.inserts, 1);
      expect(repository.collections.last.key, original.collection.key);
      expect(
        repository.collections.last.frozenJson,
        original.collection.frozenJson,
      );
      expect(generatedKeys, 1);
    },
  );

  test(
    'confirmation write failure with matching volatile cache stays unresolved after restart',
    () async {
      storage.failWrite = 3;
      expect(await controller().collect(payment(), 100000), isNull);
      expect(
        PendingPayment.decode(storage.cache[recoveryScope.storageKey]!).result,
        isNotNull,
      );
      expect(saved().result, isNull);
      expect(controller().confirmed, isNull);
      final key = saved().collection.key;
      await restart();
      await container.read(paymentCollectionProvider(scope).future);
      expect(controller().confirmed, isNull);
      expect(await controller().retrySaved(), isNotNull);
      expect(repository.inserts, 1);
      expect(repository.collections.last.key, key);
    },
  );

  test(
    'write succeeded then threw restores durable confirmation without another POST',
    () async {
      storage.throwAfterWrite = 3;
      expect(await controller().collect(payment(), 100000), isNotNull);
      expect(saved().result, isNotNull);
      await restart();
      expect(
        await container.read(paymentCollectionProvider(scope).future),
        isNotNull,
      );
      expect(repository.collections, hasLength(1));
      expect(generatedKeys, 1);
    },
  );

  test(
    'successful confirmation retained until explicit Done acknowledgement',
    () async {
      await controller().collect(payment(), 100000);
      final confirmed = saved();
      await restart();
      expect(
        await container.read(paymentCollectionProvider(scope).future),
        isNotNull,
      );
      expect(storage.disk[recoveryScope.storageKey], confirmed.encode());
      expect(await controller().collect(payment(10000), 100000), isNull);
      await controller().acknowledge();
      expect(storage.disk, isEmpty);
      expect(controller().hasSavedOperation, isFalse);
      expect(repository.collections, hasLength(1));
    },
  );

  test(
    'failed acknowledgement preserves receipt and never permits another collection',
    () async {
      await controller().collect(payment(), 100000);
      final original = saved().encode();
      storage.failDelete = true;
      await controller().acknowledge();
      expect(storage.disk[recoveryScope.storageKey], original);
      expect(controller().confirmed, isNotNull);
      expect(await controller().collect(payment(10000), 100000), isNull);
      storage.failDelete = false;
      await controller().acknowledge();
      expect(storage.disk, isEmpty);
    },
  );

  test(
    'timeout then recognized rejection cannot erase earlier uncertainty across restart',
    () async {
      repository.failure = const BillingFailure('Timeout', uncertain: true);
      await controller().collect(payment(), 100000);
      await restart();
      await container.read(paymentCollectionProvider(scope).future);
      repository.failure = const BillingFailure(
        'Overpayment',
        code: 'PAYMENT_OVERPAYMENT',
        httpStatus: 409,
      );
      await controller().retrySaved();
      expect(saved().rejected, isFalse);
      expect(saved().attempts.map((a) => a.outcome), [
        PaymentAttemptOutcome.unresolved,
        PaymentAttemptOutcome.rejected,
      ]);
      expect(await controller().collect(payment(10000), 100000), isNull);
      expect(generatedKeys, 1);
    },
  );

  test(
    'conflict persists across restart and disables exact retry and replacement',
    () async {
      repository.failure = const BillingFailure(
        'Conflict',
        uncertain: true,
        code: 'IDEMPOTENCY_KEY_CONFLICT',
        httpStatus: 409,
      );
      await controller().collect(payment(), 100000);
      await restart();
      await container.read(paymentCollectionProvider(scope).future);
      expect(saved().conflict, isTrue);
      expect(controller().canRetry, isFalse);
      expect(await controller().retrySaved(), isNull);
      expect(await controller().collect(payment(10000), 100000), isNull);
      expect(repository.collections, hasLength(1));
    },
  );

  for (final failure in [
    const BillingFailure('Generic rejection'),
    const BillingFailure('Unknown code', code: 'UNKNOWN'),
    const BillingFailure(
      'Mismatched status',
      code: 'PAYMENT_OVERPAYMENT',
      httpStatus: 400,
    ),
    const BillingFailure('Server unavailable', uncertain: true),
  ]) {
    test('${failure.message} never supplies non-commit evidence', () async {
      repository.failure = failure;
      await controller().collect(payment(), 100000);
      expect(saved().rejected, isFalse);
      expect(saved().attempts.single.outcome, PaymentAttemptOutcome.unresolved);
      expect(await controller().collect(payment(10000), 100000), isNull);
    });
  }

  test(
    'first typed rejection allows guarded replacement without deleting unresolved history',
    () async {
      repository.failure = const BillingFailure(
        'Reference rejected',
        code: 'DUPLICATE_PAYMENT_REFERENCE',
        httpStatus: 409,
      );
      await controller().collect(payment(), 100000);
      final first = saved();
      expect(first.rejected, isTrue);
      repository.failure = null;
      expect(await controller().collect(payment(10000), 100000), isNotNull);
      expect(repository.collections.last.key, isNot(first.collection.key));
      expect(repository.inserts, 1);
      expect(generatedKeys, 2);
    },
  );

  test('failed read blocks fresh requests and recheck does not POST', () async {
    storage.failRead = true;
    await expectLater(
      container.read(paymentCollectionProvider(scope).future),
      throwsA(isA<BillingFailure>()),
    );
    expect(await controller().collect(payment(), 100000), isNull);
    expect(repository.collections, isEmpty);
    expect(generatedKeys, 0);
    storage.failRead = false;
    await controller().recheck();
    expect(controller().blocked, isFalse);
    expect(repository.collections, isEmpty);
  });

  test(
    'gym change while preparing dispatch prevents POST and preserves saved data',
    () async {
      storage.gateWrite = 2;
      storage.gate = Completer<void>();
      storage.entered = Completer<void>();
      final pending = controller().collect(payment(), 100000);
      await storage.entered!.future;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      storage.gate!.complete();
      expect(await pending, isNull);
      expect(repository.collections, isEmpty);
      expect(storage.disk[recoveryScope.storageKey], isNotNull);
    },
  );

  test(
    'scope change in flight cannot apply receipt or clear the original operation',
    () async {
      final entered = Completer<void>();
      repository.beforeRecord = (_) => entered.complete();
      repository.gate = Completer<RecordedPayment>();
      final pending = controller().collect(payment(), 100000);
      await entered.future;
      repository.beforeRecord = null;
      final old = saved().encode();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await container.pump();
      expect(repository.cancellationTokens.single!.isCancelled, isTrue);
      repository.gate!.complete(
        repository.confirmation(repository.collections.single),
      );
      expect(await pending, isNull);
      expect(storage.disk[recoveryScope.storageKey], old);
      container.read(adminGymProvider.notifier).selectGym(gymA);
      await container.read(paymentCollectionProvider(scope).future);
      expect(await controller().retrySaved(), isNotNull);
      expect(repository.inserts, 1);
    },
  );

  test(
    'account isolation restores no record and makes no request under another actor',
    () async {
      storage.disk[recoveryScope.storageKey] = frozen().encode();
      final currentIdentity = adminIdentity(gyms: [gymA]);
      final other = await start(
        identity: AuthIdentity(
          user: const AuthUser(
            id: 'other-account',
            email: 'other@example.invalid',
            status: AccountStatus.active,
          ),
          gymAccess: currentIdentity.gymAccess,
        ),
      );
      addTearDown(other.dispose);
      final otherScope = (
        member: (userId: 'other-account', gymId: gymA, memberId: memberId),
        subscriptionId: subscriptionId,
      );
      expect(
        await other.read(paymentCollectionProvider(otherScope).future),
        isNull,
      );
      expect(
        other
            .read(paymentCollectionProvider(otherScope).notifier)
            .hasSavedOperation,
        isFalse,
      );
      expect(storage.disk[recoveryScope.storageKey], frozen().encode());
      expect(repository.collections, isEmpty);
    },
  );

  for (final malformed in ['corrupt JSON', 'version', 'scope', 'ledger']) {
    test(
      '$malformed recovery data is preserved and blocks new requests',
      () async {
        final json = frozen().toJson();
        if (malformed == 'version') json['version'] = 999;
        if (malformed == 'scope') {
          (json['scope'] as Map)['userId'] = 'other-account';
        }
        if (malformed == 'ledger') json['revision'] = 2;
        final encoded = malformed == 'corrupt JSON'
            ? '{bad-json'
            : jsonEncode(json);
        storage.disk[recoveryScope.storageKey] = encoded;
        await expectLater(
          container.read(paymentCollectionProvider(scope).future),
          throwsA(isA<BillingFailure>()),
        );
        expect(await controller().collect(payment(), 100000), isNull);
        expect(storage.disk[recoveryScope.storageKey], encoded);
        expect(repository.collections, isEmpty);
        expect(generatedKeys, 0);
      },
    );
  }

  test(
    'API change in flight cannot persist an old callback in the new scope',
    () async {
      // Match the live sheet's active Riverpod subscription.
      container.listen(paymentCollectionProvider(scope), (_, _) {});
      final entered = Completer<void>();
      repository.beforeRecord = (_) => entered.complete();
      repository.gate = Completer<RecordedPayment>();
      final pending = controller().collect(payment(), 100000);
      await entered.future;
      final original = saved().encode();
      container
          .read(recoveryConfigProvider.notifier)
          .change('https://other.example.invalid/api/v1/');
      await container.pump();
      expect(repository.cancellationTokens.single!.isCancelled, isTrue);
      repository.gate!.complete(
        repository.confirmation(repository.collections.single),
      );
      expect(await pending, isNull);
      expect(storage.disk[recoveryScope.storageKey], original);
      expect(storage.disk.keys, hasLength(1));
      expect(repository.collections, hasLength(1));
    },
  );

  test('all recovery scope dimensions use independent storage keys', () {
    PaymentRecoveryScope selected({
      String user = 'test-account',
      String gym = gymA,
      String member = memberId,
      String subscription = subscriptionId,
      String url = onboardingUrl,
      String environment = 'development',
    }) => PaymentRecoveryScope.fromConfig(
      AppConfig.fromValues(environmentName: environment, apiBaseUrl: url),
      userId: user,
      gymId: gym,
      memberId: member,
      subscriptionId: subscription,
    );
    final keys = [
      selected(),
      selected(user: 'other'),
      selected(gym: gymB),
      selected(member: gymB),
      selected(subscription: gymB),
      selected(url: 'https://other.example.invalid/api/v1/'),
      selected(environment: 'staging'),
    ].map((scope) => scope.storageKey).toSet();
    expect(keys, hasLength(7));
    expect(keys.every((key) => key.startsWith('gym.payment.v1.')), isTrue);
  });

  test(
    'stale store callback and unresolved acknowledgement cannot replace or delete a record',
    () async {
      final store = container.read(pendingPaymentStoreProvider);
      final prepared = await store.prepare(frozen(), guard: () {});
      final dispatch = await store.dispatch(prepared, guard: () {});
      await expectLater(
        store.dispatch(prepared, guard: () {}),
        throwsA(isA<BillingFailure>()),
      );
      await expectLater(
        store.acknowledge(dispatch, guard: () {}),
        throwsA(isA<BillingFailure>()),
      );
      expect(saved().encode(), dispatch.encode());
    },
  );

  test(
    'ordinary history and balance refresh cannot release an unresolved payment',
    () async {
      repository.failure = const BillingFailure('Timeout', uncertain: true);
      await controller().collect(payment(), 100000);
      final original = saved().encode();
      repository.failure = null;
      await repository.revenue(
        gymA,
        DashboardQuery.range(
          CalendarDate(2026, 1, 1),
          CalendarDate(2026, 1, 1),
        ),
        1,
      );
      await controller().recheck();
      expect(controller().blocked, isTrue);
      expect(storage.disk[recoveryScope.storageKey], original);
      expect(await controller().collect(payment(10000), 100000), isNull);
      expect(repository.collections, hasLength(1));
    },
  );

  test(
    'cash response lost after commit recovers across restart without a second installment',
    () async {
      repository.loseResponse = true;
      final cash = ManualPayment(
        amountPaise: 10000,
        method: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 1, 1),
      );
      expect(await controller().collect(cash, 50000), isNull);
      final original = saved();
      await restart();
      await container.read(paymentCollectionProvider(scope).future);
      expect(
        controller().savedCollection!.body.containsKey('transactionReference'),
        isFalse,
      );
      repository.loseResponse = false;
      expect(await controller().retrySaved(), isNotNull);
      expect(repository.inserts, 1);
      expect(repository.collections.last.key, original.collection.key);
      expect(
        repository.collections.last.frozenJson,
        original.collection.frozenJson,
      );
      expect(generatedKeys, 1);
    },
  );
}
