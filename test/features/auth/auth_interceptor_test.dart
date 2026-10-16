import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuthApi api;
  late FakeCredentialStorage storage;
  late AuthRepository repository;
  late Dio client;
  setUp(() async {
    api = FakeAuthApi();
    storage = FakeCredentialStorage();
    repository = AuthRepository(api: api, storage: storage);
    await repository.login(
      email: 'person@example.invalid',
      password: syntheticCredential(),
    );
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    client.interceptors.add(
      AuthInterceptor(client: client, repository: repository),
    );
  });
  tearDown(() {
    client.close(force: true);
    repository.dispose();
  });
  ResponseBody expired() =>
      jsonResponse(failureBody('INVALID_AUTHENTICATION'), status: 401);

  test('protected request receives the current bearer token', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(
        request.headers['Authorization'] ==
            'Bearer ${api.loginTokens.accessToken}',
        isTrue,
      );
      return jsonResponse(success({}));
    });
    await client.get<Object?>('protected');
  });
  test(
    'login and refresh remove stale bearer even on authenticated client',
    () async {
      client.options.headers['Authorization'] =
          'Bearer ${syntheticCredential()}';
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return jsonResponse(success({}));
      });
      await client.post<Object?>('auth/login');
      await client.post<Object?>('auth/refresh');
      expect(api.refreshCalls, 0);
    },
  );
  test(
    'expired request refreshes and retries once with rotated token',
    () async {
      var requests = 0;
      client.httpClientAdapter = CallbackAdapter((request) {
        requests++;
        if (requests == 1) return expired();
        expect(
          request.headers['Authorization'] ==
              'Bearer ${api.rotatedTokens.accessToken}',
          isTrue,
        );
        return jsonResponse(success({}));
      });
      await client.get<Object?>('protected');
      expect(requests, 2);
      expect(api.refreshCalls, 1);
    },
  );
  test(
    'protected photo bytes decode expired JSON and refresh before a safe GET retry',
    () async {
      var requests = 0;
      client.httpClientAdapter = CallbackAdapter((_) {
        requests++;
        if (requests == 1) return expired();
        return ResponseBody.fromBytes(
          Uint8List.fromList([255, 216, 255]),
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });
      final result = await client.get<List<int>>(
        'protected-photo',
        options: Options(responseType: ResponseType.bytes),
      );
      expect(result.data, [255, 216, 255]);
      expect(requests, 2);
      expect(api.refreshCalls, 1);
      expect(repository.state, isA<SessionAuthenticated>());
    },
  );
  test('second expired response stops retry and invalidates session', () async {
    var requests = 0;
    client.httpClientAdapter = CallbackAdapter((_) {
      requests++;
      return expired();
    });
    await expectLater(
      client.get<Object?>('protected'),
      throwsA(isA<DioException>()),
    );
    expect(requests, 2);
    expect(api.refreshCalls, 1);
    expect(repository.accessToken, isNull);
    expect(storage.value, isNull);
    expect(repository.state, isA<SessionError>());
  });
  test('refresh failure does not retry original request', () async {
    api.refreshFailure = const AuthFailure(AuthFailureKind.network);
    var requests = 0;
    client.httpClientAdapter = CallbackAdapter((_) {
      requests++;
      return expired();
    });
    await expectLater(
      client.get<Object?>('protected'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'safe failure',
          isA<AuthFailure>(),
        ),
      ),
    );
    expect(requests, 1);
    expect(api.refreshCalls, 1);
    expect(storage.value, isNull);
    expect(repository.accessToken, isNull);
  });
  test('concurrent expired requests perform ONE refresh request', () async {
    api.refreshGate = Completer<void>();
    final originalsArrived = Completer<void>();
    var originals = 0;
    var retries = 0;
    client.httpClientAdapter = CallbackAdapter((request) {
      if (request.headers['Authorization'] ==
          'Bearer ${api.loginTokens.accessToken}') {
        originals++;
        if (originals == 2) originalsArrived.complete();
        return expired();
      }
      retries++;
      expect(
        request.headers['Authorization'] ==
            'Bearer ${api.rotatedTokens.accessToken}',
        isTrue,
      );
      return jsonResponse(success({}));
    });
    final pending = Future.wait([
      client.get<Object?>('protected/first'),
      client.get<Object?>('protected/second'),
    ]);
    await originalsArrived.future;
    await api.refreshEntered.future;
    expect(api.refreshCalls, 1);
    api.refreshGate!.complete();
    await pending;
    expect(api.refreshCalls, 1);
    expect(retries, 2);
  });
  test(
    'late old-token 401 reuses the rotation instead of replaying refresh',
    () async {
      final releaseLate = Completer<void>();
      final lateArrived = Completer<void>();
      client.httpClientAdapter = CallbackAdapter((request) async {
        final old =
            request.headers['Authorization'] ==
            'Bearer ${api.loginTokens.accessToken}';
        if (old && request.path.endsWith('/late')) {
          lateArrived.complete();
          await releaseLate.future;
          return expired();
        }
        if (old) return expired();
        return jsonResponse(success({}));
      });
      final late = client.get<Object?>('protected/late');
      await lateArrived.future;
      await client.get<Object?>('protected/first');
      releaseLate.complete();
      await late;
      expect(api.refreshCalls, 1);
    },
  );
  test('401 invalid credentials never triggers a refresh', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(failureBody('INVALID_CREDENTIALS'), status: 401),
    );
    await expectLater(
      client.get<Object?>('protected'),
      throwsA(isA<DioException>()),
    );
    expect(api.refreshCalls, 0);
  });
  test('external origin is rejected before credentials or transport', () async {
    final adapter = CallbackAdapter((_) => jsonResponse(success({})));
    client.httpClientAdapter = adapter;
    await expectLater(
      client.get<Object?>('https://other.example.invalid/protected'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, isEmpty);
  });
  test('logout while request is pending prevents refresh or retry', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    client.httpClientAdapter = CallbackAdapter((_) async {
      arrived.complete();
      await release.future;
      return expired();
    });
    final request = client.get<Object?>('protected');
    final expectation = expectLater(request, throwsA(isA<DioException>()));
    await arrived.future;
    await repository.logout();
    release.complete();
    await expectation;
    expect(api.refreshCalls, 0);
  });
  test(
    'multipart is not replayed and recovered session remains authenticated',
    () async {
      var requests = 0;
      client.httpClientAdapter = CallbackAdapter((_) {
        requests++;
        return expired();
      });
      await expectLater(
        client.post<Object?>(
          'protected',
          data: FormData.fromMap({'note': 'test'}),
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'retry failure',
            isA<AuthFailure>().having(
              (error) => error.kind,
              'kind',
              AuthFailureKind.retryRequired,
            ),
          ),
        ),
      );
      expect(requests, 1);
      expect(api.refreshCalls, 1);
      expect(repository.state, isA<SessionAuthenticated>());
    },
  );
  test(
    'retry from a previous account revision cannot attach a new bearer',
    () async {
      final previousRevision = repository.revision;
      await repository.login(
        email: 'other@example.invalid',
        password: syntheticCredential(),
      );
      final adapter = CallbackAdapter((_) => jsonResponse(success({})));
      client.httpClientAdapter = adapter;
      await expectLater(
        client.get<Object?>(
          'protected',
          options: Options(
            extra: {'authRetried': true, 'authRevision': previousRevision},
          ),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, isEmpty);
    },
  );
}
