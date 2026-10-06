import 'dart:async';
import 'dart:io';

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
  for (final phase in ['persistence', 'me']) {
    for (final succeeds in [true, false]) {
      test(
        'old-token 401 joins pending $phase (${succeeds ? 'success' : 'failure'})',
        () async {
          final api = FakeAuthApi();
          final storage = FakeCredentialStorage();
          final repository = AuthRepository(api: api, storage: storage);
          addTearDown(repository.dispose);
          await repository.login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
          final client = createApiClient(
            AppConfig.fromValues(
              apiBaseUrl: 'https://api.example.invalid/api/v1/',
            ),
          );
          addTearDown(() => client.close(force: true));
          client.interceptors.add(
            AuthInterceptor(client: client, repository: repository),
          );
          final arrived = Completer<void>();
          final release401 = Completer<void>();
          final recoveryGate = Completer<void>();
          var attempts = 0;
          var completed = false;
          client.httpClientAdapter = CallbackAdapter((request) async {
            attempts++;
            if (attempts == 1) {
              arrived.complete();
              await release401.future;
              return jsonResponse(
                failureBody('INVALID_AUTHENTICATION'),
                status: 401,
              );
            }
            expect(
              request.headers['Authorization'] ==
                  'Bearer ${api.rotatedTokens.accessToken}',
              isTrue,
            );
            expect(repository.state, isA<SessionAuthenticated>());
            return jsonResponse(success({}));
          });
          final request = client
              .get<Object?>('protected')
              .whenComplete(() => completed = true);
          final requestResult = succeeds
              ? expectLater(request, completes)
              : expectLater(request, throwsA(isA<DioException>()));
          await arrived.future;
          if (phase == 'persistence') {
            storage.writeGate = recoveryGate;
            storage.writeEntered = Completer<void>();
            storage.failWrite = !succeeds;
          } else {
            api.meGate = recoveryGate;
            if (!succeeds) {
              api.meFailure = const AuthFailure(AuthFailureKind.invalidSession);
            }
          }
          final recovery = repository.refreshSession();
          final recoveryResult = succeeds
              ? expectLater(recovery, completes)
              : expectLater(recovery, throwsA(isA<AuthFailure>()));
          await (phase == 'persistence'
              ? storage.writeEntered!.future
              : api.meEntered.future);
          final newRequest = client.get<Object?>('protected/new');
          final newRequestResult = succeeds
              ? expectLater(newRequest, completes)
              : expectLater(newRequest, throwsA(isA<DioException>()));
          release401.complete();
          // Drain Dio's interceptor microtasks while the recovery is held.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(completed, isFalse);
          expect(attempts, 1);
          expect(api.refreshCalls, 1);
          expect(repository.accessToken, isNull);
          recoveryGate.complete();
          await Future.wait([requestResult, newRequestResult, recoveryResult]);
          expect(api.refreshCalls, 1);
          expect(attempts, succeeds ? 3 : 1);
          if (!succeeds) {
            expect(repository.accessToken, isNull);
            expect(storage.value, isNull);
            expect(repository.state, isA<SessionError>());
          }
        },
      );
    }
  }

  test('real transport refuses redirect even when caller enables it', () async {
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await origin.close(force: true);
      await destination.close(force: true);
    });
    var destinationCalls = 0;
    var originCalls = 0;
    destination.listen((request) async {
      destinationCalls++;
      await request.response.close();
    });
    final api = FakeAuthApi();
    final repository = AuthRepository(
      api: api,
      storage: FakeCredentialStorage(),
    );
    addTearDown(repository.dispose);
    await repository.login(
      email: 'person@example.invalid',
      password: syntheticCredential(),
    );
    origin.listen((request) async {
      originCalls++;
      expect(
        request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer ${api.loginTokens.accessToken}',
        isTrue,
      );
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${destination.port}/unexpected',
      );
      await request.response.close();
    });
    final client = createApiClient(
      AppConfig.fromValues(
        apiBaseUrl: 'http://127.0.0.1:${origin.port}/api/v1/',
      ),
    );
    addTearDown(() => client.close(force: true));
    client.interceptors.add(
      AuthInterceptor(client: client, repository: repository),
    );
    await expectLater(
      client.get<Object?>('protected', options: Options(followRedirects: true)),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          302,
        ),
      ),
    );
    expect(originCalls, 1);
    expect(destinationCalls, 0);
    expect(api.refreshCalls, 0);
  });
}
