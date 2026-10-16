import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/memberships/data/pending_renewal_store.dart';
import 'package:gym_management_app/features/memberships/data/renewal_repository.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/models/renewal_operation.dart';
import 'package:gym_management_app/features/memberships/models/renewal_payment_draft.dart';
import 'package:gym_management_app/features/memberships/models/renewal_preview.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/memberships/providers/renewal_providers.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import '../members/member_fakes.dart';
import '../members/member_repository_test.dart' show envelope;
import '../members/onboarding_fakes.dart' show onboardingUrl;
import 'billing_fakes.dart';
import 'payment_recovery_test.dart' show RecoveryDisk;
import 'renewal_fakes.dart';

void main() {
  final preview = RenewalPreview.fromJson(renewalPreviewJson());
  for (final choice in RenewalPaymentChoice.values) {
    test(
      'payment choice $choice uses integer paise and safe optional payment',
      () {
        final draft = RenewalPaymentDraft(choice: choice, amount: '500.01');
        expect(
          draft.amountPaise(150000),
          choice == RenewalPaymentChoice.full
              ? 150000
              : choice == RenewalPaymentChoice.partial
              ? 50001
              : 0,
        );
        expect(draft.payment(0, DateTime.now().toUtc()), isNull);
      },
    );
  }
  for (final amount in ['0', '-1', '1500.01', '1.001', 'abc']) {
    test('invalid partial amount $amount is rejected', () {
      expect(
        RenewalPaymentDraft(
          choice: RenewalPaymentChoice.partial,
          amount: amount,
        ).validation(150000),
        isNotNull,
      );
    });
  }
  for (final method in PaymentMethod.values) {
    test('$method reference requirements reused', () {
      expect(
        RenewalPaymentDraft(method: method).validation(150000),
        method.requiresReference ? isNotNull : isNull,
      );
    });
  }
  test(
    'request freezes millisecond timestamp and optional payment omission',
    () {
      final payment = ManualPayment(
        amountPaise: 50000,
        method: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 1, 1, 10, 0, 0, 123, 456),
      );
      final request = RenewalOperationRequest.fromPreview(
        preview,
        'test-renewal-key',
        payment,
      );
      expect(request.body['payment']['paidAt'], '2026-01-01T10:00:00.123Z');
      expect(request.balancePaise, 100000);
      expect(
        RenewalOperationRequest.frozen(
          request.frozenJson,
          request.key,
        ).frozenJson,
        request.frozenJson,
      );
      final body = request.body;
      body['expectedTerms']['pricePaise'] = 999;
      expect(request.pricePaise, 150000);
      expect(
        RenewalOperationRequest.fromPreview(
          preview,
          'test-renewal-key',
          null,
        ).body.containsKey('payment'),
        false,
      );
    },
  );
  test(
    'repository sends scoped atomic request/key and validates real receipt',
    () async {
      final dio = createApiClient(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
      );
      addTearDown(() => dio.close(force: true));
      final request = RenewalOperationRequest.fromPreview(
        preview,
        'test-renewal-key',
        ManualPayment(
          amountPaise: 50000,
          method: PaymentMethod.cash,
          paidAt: DateTime.now().toUtc(),
        ),
      );
      dio.httpClientAdapter = CallbackAdapter((options) {
        expect(options.method, 'POST');
        expect(
          options.uri.path,
          '/api/v1/gyms/$gymA/subscriptions/$subscriptionId/renew',
        );
        expect(options.headers['Idempotency-Key'], request.key);
        expect(options.data, request.body);
        return jsonResponse(envelope(renewalResultJson(request)), status: 201);
      });
      final result = await DioRenewalRepository(
        dio,
      ).complete(gymA, memberId, subscriptionId, request);
      expect(result.receivedPaise, 50000);
      expect(result.balancePaise, 100000);
    },
  );
  test(
    'repository preview uses selected plan filter and rejects mismatched scope',
    () async {
      final dio = createApiClient(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
      );
      addTearDown(() => dio.close(force: true));
      dio.httpClientAdapter = CallbackAdapter((options) {
        expect(options.queryParameters, {'planId': planId});
        return jsonResponse(envelope(renewalPreviewJson()..['gymId'] = gymB));
      });
      await expectLater(
        DioRenewalRepository(
          dio,
        ).preview(gymA, memberId, subscriptionId, planId),
        throwsA(isA<BillingFailure>()),
      );
    },
  );
  for (final failure in [
    (409, 'RENEWAL_PREVIEW_CHANGED', false),
    (409, 'ACTIVE_MEMBERSHIP_EXISTS', false),
    (400, 'ACTIVE_MEMBERSHIP_EXISTS', true),
    (409, 'IDEMPOTENCY_KEY_CONFLICT', true),
    (500, 'INTERNAL_SERVER_ERROR', true),
    (409, 'UNKNOWN_CODE', true),
    (400, 'RENEWAL_PREVIEW_CHANGED', true),
  ]) {
    test(
      'repository failure ${failure.$1}/${failure.$2} uncertainty is conservative',
      () async {
        final dio = createApiClient(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        );
        addTearDown(() => dio.close(force: true));
        dio.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': false,
            'error': {'code': failure.$2, 'message': 'PRIVATE'},
          }, status: failure.$1),
        );
        await expectLater(
          DioRenewalRepository(dio).complete(
            gymA,
            memberId,
            subscriptionId,
            RenewalOperationRequest.fromPreview(
              preview,
              'test-renewal-key',
              null,
            ),
          ),
          throwsA(
            isA<BillingFailure>()
                .having((e) => e.uncertain, 'uncertain', failure.$3)
                .having((e) => e.message, 'safe', isNot(contains('PRIVATE'))),
          ),
        );
      },
    );
  }
  late RecoveryDisk storage;
  late FakeRenewalRepository repository;
  late ProviderContainer container;
  late MembershipRequest requestScope;
  late RenewalController controller;
  int keys = 0;
  Future<void> setup(RecoveryDisk disk) async {
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        ),
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        memberRepositoryProvider.overrideWithValue(
          FakeMemberRepository()..historyRecords = expiredHistoryFixture(),
        ),
        renewalRepositoryProvider.overrideWithValue(repository),
        pendingRenewalStoreProvider.overrideWithValue(
          PendingRenewalStore(storage: disk, queue: OnboardingOperationQueue()),
        ),
        paymentKeyFactoryProvider.overrideWithValue(
          () => 'test-renewal-key-${++keys}',
        ),
      ],
    );
    await container
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
    requestScope = (
      scope: scopeFor(container.read(adminGymProvider)!, memberId),
      subscriptionId: subscriptionId,
    );
    controller = container.read(
      renewalControllerProvider(requestScope).notifier,
    );
    await container.read(renewalControllerProvider(requestScope).future);
  }

  setUp(() async {
    keys = 0;
    storage = RecoveryDisk();
    repository = FakeRenewalRepository();
    await setup(storage);
  });
  tearDown(() => container.dispose());

  test(
    'active membership blocks fresh renewal before a key or prepared record exists',
    () async {
      (container.read(memberRepositoryProvider) as FakeMemberRepository)
          .historyRecords = [
        subscriptionJson(),
      ];
      expect(await controller.submit(preview, null), isNull);
      expect(keys, 0);
      expect(storage.disk, isEmpty);
      expect(repository.requests, isEmpty);
      expect(controller.saved, isNull);
      expect(
        container.read(renewalControllerProvider(requestScope)).error,
        isA<BillingFailure>(),
      );
    },
  );
  test(
    'prepare and dispatch are durable before repository call; confirmed retained until acknowledgement',
    () async {
      expect(controller.canStart, true);
      final result = await controller.submit(preview, null);
      expect(result, isNotNull);
      expect(storage.writes.length, 3);
      final marker = PendingRenewal.decode(storage.writes[1]);
      expect(marker.attempts.single.outcome, RenewalOutcome.unresolved);
      expect(controller.saved!.result, isNotNull);
      expect(repository.insertions, 1);
      expect(await controller.submit(preview, null), isNull);
      await controller.acknowledge();
      expect(storage.disk, isEmpty);
      expect(controller.canStart, true);
    },
  );
  test(
    'lost committed response restarts and exactly replays body, key and timestamp without duplicates',
    () async {
      repository.loseResponse = true;
      final payment = ManualPayment(
        amountPaise: 50000,
        method: PaymentMethod.cash,
        paidAt: DateTime.now().toUtc(),
      );
      expect(await controller.submit(preview, payment), isNull);
      final frozen = repository.requests.single;
      expect(repository.insertions, 1);
      container.dispose();
      await setup(storage.restart());
      repository.loseResponse = false;
      // The committed successor now blocks NEW operations, but never exact replay.
      (container.read(memberRepositoryProvider) as FakeMemberRepository)
          .historyRecords = [
        subscriptionJson(),
      ];
      final result = await controller.retrySaved();
      expect(result!.receivedPaise, 50000);
      expect(repository.requests.last.frozenJson, frozen.frozenJson);
      expect(repository.requests.last.key, frozen.key);
      expect(repository.insertions, 1);
      expect(keys, 1);
    },
  );
  test(
    'confirmed restart returns saved result without any second POST',
    () async {
      await controller.submit(preview, null);
      final calls = repository.requests.length;
      container.dispose();
      await setup(storage.restart());
      expect(controller.confirmed, isNotNull);
      expect(repository.requests.length, calls);
      expect(controller.canStart, false);
      await controller.acknowledge();
      expect(storage.disk, isEmpty);
    },
  );
  test(
    'failed dispatch commit changes volatile cache but sends no request',
    () async {
      storage.failWrite = 2;
      expect(await controller.submit(preview, null), isNull);
      expect(repository.requests, isEmpty);
      expect(
        PendingRenewal.decode(storage.disk.values.single).attempts,
        isEmpty,
      );
      container.dispose();
      await setup(storage.restart());
      expect(await controller.retrySaved(), isNotNull);
      expect(repository.insertions, 1);
      expect(keys, 1);
    },
  );
  test(
    'confirmation write failure is recovered by exact replay after restart',
    () async {
      storage.failWrite = 3;
      expect(await controller.submit(preview, null), isNull);
      expect(controller.confirmed, isNull);
      expect(repository.insertions, 1);
      final key = repository.requests.single.key;
      container.dispose();
      await setup(storage.restart());
      expect(await controller.retrySaved(), isNotNull);
      expect(repository.requests.last.key, key);
      expect(repository.insertions, 1);
    },
  );
  test(
    'write-succeeded-then-threw confirmation is recovered from durable read',
    () async {
      storage.throwAfterWrite = 3;
      expect(await controller.submit(preview, null), isNotNull);
      expect(repository.insertions, 1);
      expect(controller.confirmed, isNotNull);
    },
  );
  test(
    'first definite rejection permits guarded corrected request; prior ambiguity never does',
    () async {
      repository.billing.failure = const BillingFailure(
        'Terms changed.',
        code: 'RENEWAL_PREVIEW_CHANGED',
        httpStatus: 409,
      );
      await controller.submit(preview, null);
      expect(controller.saved!.rejected, true);
      expect(controller.canStart, true);
      final first = repository.requests.single.key;
      repository.billing.failure = null;
      expect(await controller.submit(preview, null), isNotNull);
      expect(repository.requests.last.key, isNot(first));
      expect(repository.insertions, 1);
    },
  );
  test(
    'timeout followed by rejection retains earlier uncertainty and blocks replacement',
    () async {
      repository.billing.failure = const BillingFailure(
        'Timeout.',
        uncertain: true,
      );
      await controller.submit(preview, null);
      repository.billing.failure = const BillingFailure(
        'Terms changed.',
        code: 'RENEWAL_PREVIEW_CHANGED',
        httpStatus: 409,
      );
      await controller.retrySaved();
      expect(controller.saved!.rejected, false);
      expect(controller.canStart, false);
      expect(await controller.submit(preview, null), isNull);
      expect(keys, 1);
    },
  );
  test('conflict blocks automatic correction and exact retry', () async {
    repository.billing.failure = const BillingFailure(
      'Conflict.',
      uncertain: true,
      code: 'IDEMPOTENCY_KEY_CONFLICT',
      httpStatus: 409,
    );
    await controller.submit(preview, null);
    expect(controller.saved!.conflict, true);
    expect(controller.canRetry, false);
    expect(await controller.submit(preview, null), isNull);
    expect(keys, 1);
  });
  test(
    'read-back failure after dispatch commit blocks POST and remains recoverable',
    () async {
      storage.gateWrite = 2;
      storage.entered = Completer<void>();
      storage.gate = Completer<void>();
      final submitting = controller.submit(preview, null);
      await storage.entered!.future;
      storage.failRead = true;
      storage.gate!.complete();
      await submitting;
      expect(repository.requests, isEmpty);
      storage.failRead = false;
      container.dispose();
      await setup(storage.restart());
      expect(await controller.retrySaved(), isNotNull);
      expect(keys, 1);
    },
  );
  test(
    'scope change at dispatch persistence prevents repository call',
    () async {
      storage.gateWrite = 2;
      storage.entered = Completer<void>();
      storage.gate = Completer<void>();
      final submitting = controller.submit(preview, null);
      await storage.entered!.future;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      storage.gate!.complete();
      await submitting;
      expect(repository.requests, isEmpty);
      expect(storage.disk, isNotEmpty);
    },
  );
  test('concurrent submissions reuse one operation', () async {
    storage.gateWrite = 2;
    storage.entered = Completer<void>();
    storage.gate = Completer<void>();
    final first = controller.submit(preview, null);
    await storage.entered!.future;
    expect(await controller.submit(preview, null), isNull);
    storage.gate!.complete();
    expect(await first, isNotNull);
    expect(repository.requests.length, 1);
    expect(keys, 1);
  });
  test(
    'renewal uses a separate slot and never rewrites a saved installment',
    () async {
      final scope = PaymentRecoveryScope.fromConfig(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        userId: requestScope.scope.userId,
        gymId: gymA,
        memberId: memberId,
        subscriptionId: subscriptionId,
      );
      storage.disk[scope.storageKey] = 'unchanged legacy installment record';
      await controller.submit(preview, null);
      await controller.acknowledge();
      expect(
        storage.disk[scope.storageKey],
        'unchanged legacy installment record',
      );
      expect(storage.disk.length, 1);
    },
  );
  test(
    'guarded store rejects stale revision and wrong identity, preserving saved operation',
    () async {
      final store = container.read(pendingRenewalStoreProvider);
      final scope = PaymentRecoveryScope.fromConfig(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        userId: requestScope.scope.userId,
        gymId: gymA,
        memberId: memberId,
        subscriptionId: subscriptionId,
      );
      final prepared = PendingRenewal(
        scope: scope,
        createdAt: DateTime.now().toUtc(),
        request: RenewalOperationRequest.fromPreview(
          preview,
          'store-renewal-key',
          null,
        ),
      );
      await store.prepare(prepared, guard: () {});
      await store.dispatch(prepared, guard: () {});
      await expectLater(
        store.dispatch(prepared, guard: () {}),
        throwsA(isA<BillingFailure>()),
      );
      final wrong = PendingRenewal(
        scope: scope,
        createdAt: prepared.createdAt,
        request: RenewalOperationRequest.fromPreview(
          preview,
          'wrong-renewal-key',
          null,
        ),
      );
      await expectLater(
        store.dispatch(wrong, guard: () {}),
        throwsA(isA<BillingFailure>()),
      );
      expect((await store.read(scope))!.request.key, 'store-renewal-key');
      expect((await store.read(scope))!.attempts.length, 1);
    },
  );
  test(
    'corrupt renewal storage blocks restoration instead of starting a new operation',
    () async {
      final scope = PaymentRecoveryScope.fromConfig(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        userId: requestScope.scope.userId,
        gymId: gymA,
        memberId: memberId,
        subscriptionId: subscriptionId,
      );
      storage.disk[scope.storageKey.replaceFirst(
            '.pending',
            '.renewal.pending',
          )] =
          'corrupt';
      await controller.recheck();
      expect(controller.ready, false);
      expect(await controller.submit(preview, null), isNull);
      expect(repository.requests, isEmpty);
      expect(storage.disk.values.single, 'corrupt');
    },
  );
}
