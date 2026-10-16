import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_repository.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'onboarding_fakes.dart';

void main() {
  late Dio client;
  late DioMemberOnboardingRepository repository;
  setUp(() {
    client = createApiClient(AppConfig.fromValues(apiBaseUrl: onboardingUrl));
    repository = DioMemberOnboardingRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'legacy frozen timestamp is sent unchanged and a millisecond confirmation is accepted',
    () async {
      final body = onboardingRequest(membership: true, amount: 40000).toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final original = jsonEncode(body);
      final operation = pendingOperation(
        request: OnboardingRequest.fromFrozenJson(original),
      );
      client.httpClientAdapter = CallbackAdapter((options) {
        expect(jsonEncode(options.data), original);
        expect(options.headers['Idempotency-Key'], operation.idempotencyKey);
        final result = onboardingResultJson(operation.request);
        expect(result['payment']['paidAt'], '2026-01-01T10:00:00.123Z');
        return jsonResponse(success(result), status: 201);
      });
      final result = await repository.complete(
        gymA,
        operation.request,
        operation.idempotencyKey,
      );
      expect(result.payment!.paidAt, DateTime.utc(2026, 1, 1, 10, 0, 0, 123));
      expect(operation.request.frozenJson, original);
    },
  );
  for (final membership in [false, true]) {
    test(
      'sends exact atomic ${membership ? 'membership' : 'member-only'} request and unchanged key',
      () async {
        final operation = pendingOperation(
          request: onboardingRequest(
            membership: membership,
            amount: membership ? 40000 : null,
          ),
        );
        final adapter = CallbackAdapter((options) {
          expect(options.method, 'POST');
          expect(
            options.uri.path,
            '/api/v1/gyms/$gymA/member-onboarding/complete',
          );
          expect(options.queryParameters, isEmpty);
          expect(options.headers['Idempotency-Key'], operation.idempotencyKey);
          expect(options.data, operation.request.toJson());
          return jsonResponse(
            success(onboardingResultJson(operation.request)),
            status: 201,
          );
        });
        client.httpClientAdapter = adapter;
        final result = await repository.complete(
          gymA,
          operation.request,
          operation.idempotencyKey,
        );
        expect(result.operationId, onboardingOperationId);
        expect(adapter.requests, hasLength(1));
      },
    );
  }
  test('malformed gym/key fails before network I/O', () async {
    final adapter = CallbackAdapter(
      (_) => throw StateError('Unexpected network call'),
    );
    client.httpClientAdapter = adapter;
    for (final pair in [
      ('bad', 'valid-key'),
      (gymA, 'short'),
      (gymA, 'bad key value'),
    ]) {
      await expectLater(
        repository.complete(pair.$1, onboardingRequest(), pair.$2),
        throwsA(
          isA<OnboardingFailure>().having(
            (e) => e.kind,
            'kind',
            OnboardingFailureKind.validation,
          ),
        ),
      );
    }
    expect(adapter.requests, isEmpty);
  });
  for (final scenario in [
    (400, 'VALIDATION_ERROR', OnboardingFailureKind.validation, false),
    (401, 'INVALID_AUTHENTICATION', OnboardingFailureKind.authorization, false),
    (403, 'FORBIDDEN', OnboardingFailureKind.authorization, false),
    (404, 'PLAN_NOT_FOUND', OnboardingFailureKind.resourceNotFound, false),
    (409, 'IDEMPOTENCY_KEY_CONFLICT', OnboardingFailureKind.conflict, false),
    (409, 'DUPLICATE_MEMBER_CODE', OnboardingFailureKind.conflict, false),
    (429, 'RATE_LIMITED', OnboardingFailureKind.rateLimited, false),
    (
      503,
      'ONBOARDING_STORAGE_UNAVAILABLE',
      OnboardingFailureKind.storageUnavailable,
      false,
    ),
    (500, 'INTERNAL_ERROR', OnboardingFailureKind.server, true),
    (404, 'UNKNOWN_ERROR', OnboardingFailureKind.unexpectedResponse, true),
    (429, 'UNKNOWN_ERROR', OnboardingFailureKind.unexpectedResponse, true),
    (500, 'PLAN_NOT_FOUND', OnboardingFailureKind.server, true),
  ]) {
    test('maps ${scenario.$1} ${scenario.$2} safely without retry', () async {
      final adapter = CallbackAdapter(
        (_) => jsonResponse(failureBody(scenario.$2), status: scenario.$1),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.complete(gymA, onboardingRequest(), 'synthetic-key'),
        throwsA(
          isA<OnboardingFailure>()
              .having((e) => e.kind, 'kind', scenario.$3)
              .having((e) => e.uncertain, 'uncertain', scenario.$4),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });
  }
  for (final scenario in [
    (AuthFailureKind.invalidCredentials, OnboardingFailureKind.authorization),
    (AuthFailureKind.invalidSession, OnboardingFailureKind.authorization),
    (AuthFailureKind.forbidden, OnboardingFailureKind.authorization),
    (AuthFailureKind.validation, OnboardingFailureKind.validation),
    (AuthFailureKind.rateLimited, OnboardingFailureKind.rateLimited),
    (AuthFailureKind.network, OnboardingFailureKind.network),
    (AuthFailureKind.server, OnboardingFailureKind.server),
    (AuthFailureKind.storage, OnboardingFailureKind.localStorage),
    (AuthFailureKind.configuration, OnboardingFailureKind.configuration),
    (AuthFailureKind.retryRequired, OnboardingFailureKind.retryRequired),
    (
      AuthFailureKind.unexpectedResponse,
      OnboardingFailureKind.unexpectedResponse,
    ),
  ]) {
    test(
      'wrapped ${scenario.$1} preserves its cause and uncertainty',
      () async {
        final adapter = CallbackAdapter(
          (options) => throw DioException(
            requestOptions: options,
            error: AuthFailure(scenario.$1),
          ),
        );
        client.httpClientAdapter = adapter;
        await expectLater(
          repository.complete(gymA, onboardingRequest(), 'synthetic-key'),
          throwsA(
            isA<OnboardingFailure>()
                .having((e) => e.kind, 'kind', scenario.$2)
                .having((e) => e.uncertain, 'uncertain', true),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );
  }
  for (final type in [
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.cancel,
  ]) {
    test('$type preserves uncertain outcome without transport retry', () async {
      final adapter = CallbackAdapter(
        (options) => throw DioException(requestOptions: options, type: type),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.complete(gymA, onboardingRequest(), 'synthetic-key'),
        throwsA(
          isA<OnboardingFailure>()
              .having((e) => e.kind, 'kind', OnboardingFailureKind.network)
              .having((e) => e.uncertain, 'uncertain', true),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });
  }
  test(
    'unreadable success, missing meta and wrong gym are uncertain confirmations',
    () async {
      final request = onboardingRequest();
      for (final body in [
        {
          'success': true,
          'data': {},
          'meta': {'requestId': 'synthetic'},
        },
        {'success': true, 'data': onboardingResultJson(request)},
        success(onboardingResultJson(request, gymId: gymB)),
        {
          'success': false,
          'data': onboardingResultJson(request),
          'meta': {'requestId': 'synthetic'},
        },
      ]) {
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse(body, status: 201),
        );
        await expectLater(
          repository.complete(gymA, request, 'synthetic-key'),
          throwsA(
            isA<OnboardingFailure>()
                .having(
                  (e) => e.kind,
                  'kind',
                  OnboardingFailureKind.unexpectedResponse,
                )
                .having((e) => e.uncertain, 'uncertain', true),
          ),
        );
      }
    },
  );
  for (final scenario in [
    (AuthFailureKind.network, OnboardingFailureKind.network),
    (AuthFailureKind.server, OnboardingFailureKind.server),
    (AuthFailureKind.storage, OnboardingFailureKind.localStorage),
  ]) {
    test('real interceptor refresh failure preserves ${scenario.$1}', () async {
      final api = FakeAuthApi()..identity = adminIdentity();
      final auth = AuthRepository(api: api, storage: FakeCredentialStorage());
      addTearDown(auth.dispose);
      await auth.login(
        email: 'person@example.invalid',
        password: syntheticCredential(),
      );
      api.refreshFailure = AuthFailure(scenario.$1);
      client.interceptors.add(
        AuthInterceptor(client: client, repository: auth),
      );
      final adapter = CallbackAdapter(
        (_) => jsonResponse(failureBody('INVALID_AUTHENTICATION'), status: 401),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.complete(gymA, onboardingRequest(), 'synthetic-key'),
        throwsA(
          isA<OnboardingFailure>()
              .having((e) => e.kind, 'kind', scenario.$2)
              .having((e) => e.uncertain, 'uncertain', true),
        ),
      );
      expect(api.refreshCalls, 1);
      expect(adapter.requests, hasLength(1));
    });
  }
  test(
    'existing authentication interceptor retains body/key across its single 401 retry',
    () async {
      final api = FakeAuthApi()..identity = adminIdentity();
      final auth = AuthRepository(api: api, storage: FakeCredentialStorage());
      addTearDown(auth.dispose);
      await auth.login(
        email: 'person@example.invalid',
        password: syntheticCredential(),
      );
      client.interceptors.add(
        AuthInterceptor(client: client, repository: auth),
      );
      final operation = pendingOperation(
        request: onboardingRequest(membership: true, amount: 40000),
      );
      final bodies = <String>[];
      final keys = <String>[];
      client.httpClientAdapter = CallbackAdapter((options) {
        bodies.add(jsonEncode(options.data));
        keys.add(options.headers['Idempotency-Key'] as String);
        expect(options.headers['Authorization'], startsWith('Bearer '));
        if (bodies.length == 1) {
          return jsonResponse(
            failureBody('INVALID_AUTHENTICATION'),
            status: 401,
          );
        }
        return jsonResponse(
          success(onboardingResultJson(operation.request)),
          status: 201,
        );
      });
      await repository.complete(
        gymA,
        operation.request,
        operation.idempotencyKey,
      );
      expect(bodies, [
        operation.request.frozenJson,
        operation.request.frozenJson,
      ]);
      expect(keys, [operation.idempotencyKey, operation.idempotencyKey]);
      expect(api.refreshCalls, 1);
    },
  );
}
