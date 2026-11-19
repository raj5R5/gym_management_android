import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_api_service.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_diagnostics.dart';

import 'auth_fakes.dart';

void main() {
  late Dio client;
  late DioAuthApiService api;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    api = DioAuthApiService(client);
  });
  tearDown(() => client.close(force: true));

  test(
    'refresh diagnostics retain failure stage and HTTP metadata, not payloads',
    () async {
      final lines = <String>[];
      api = DioAuthApiService(
        client,
        diagnostics: AuthDiagnostics(sink: lines.add),
      );
      final credential = syntheticCredential();
      const id = 'a4eb1081-e162-4f8a-9cb1-91d918503315';
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': false,
          'error': {'code': 'INTERNAL_SERVER_ERROR', 'message': credential},
          'meta': {'requestId': id},
        }, status: 503),
      );
      await expectLater(
        api.refresh(credential),
        throwsA(
          isA<AuthFailure>()
              .having((e) => e.kind, 'kind', AuthFailureKind.server)
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.requestId, 'requestId', id),
        ),
      );
      expect(
        lines.last,
        contains('stage=refreshApi event=failed category=server http=503'),
      );
      expect(lines.join().contains(credential), isFalse);
    },
  );

  test(
    'malformed successful me response is distinguishable from invalid auth',
    () async {
      final lines = <String>[];
      api = DioAuthApiService(
        client,
        diagnostics: AuthDiagnostics(sink: lines.add),
      );
      final token = syntheticCredential();
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(success({})),
      );
      await expectLater(
        api.currentUser(token),
        throwsA(
          isA<AuthFailure>()
              .having((e) => e.kind, 'kind', AuthFailureKind.unexpectedResponse)
              .having((e) => e.statusCode, 'statusCode', 200),
        ),
      );
      expect(lines.last, contains('stage=currentUserApi event=failed'));
      expect(lines.join().contains(token), isFalse);
    },
  );

  test(
    'mobile login and refresh use exact contracts without stale headers',
    () async {
      final tokens = syntheticTokens();
      final rotated = syntheticTokens();
      final password = syntheticCredential();
      client.options.headers['Authorization'] =
          'Bearer ${syntheticCredential()}';
      client.options.headers['Origin'] = 'https://example.invalid';
      client.options.headers['Cookie'] = syntheticCredential();
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], isNull);
        expect(request.headers['Origin'], isNull);
        expect(request.headers['Cookie'], isNull);
        if (request.uri.path == '/api/v1/auth/login') {
          expect(request.method, 'POST');
          final body = request.data as Map;
          expect(body.keys.toSet(), {'email', 'password', 'client'});
          expect(body['email'], 'person@example.invalid');
          expect(body['password'] == password, isTrue);
          expect(body['client'], 'mobile');
          return jsonResponse(
            success({...identityJson(), ...tokenJson(tokens)}),
          );
        }
        expect(request.uri.path, '/api/v1/auth/refresh');
        expect(
          (request.data as Map)['refreshToken'] == tokens.refreshToken,
          isTrue,
        );
        return jsonResponse(success(tokenJson(rotated)));
      });
      final login = await api.login(
        email: ' person@example.invalid ',
        password: password,
      );
      expect(login.identity.gymAccess, isEmpty);
      expect(login.tokens.refreshToken == tokens.refreshToken, isTrue);
      final result = await api.refresh(tokens.refreshToken);
      expect(result.refreshToken == rotated.refreshToken, isTrue);
    },
  );
  test(
    'me uses explicit bearer; logout uses refresh JSON without bearer',
    () async {
      final tokens = syntheticTokens();
      client.httpClientAdapter = CallbackAdapter((request) {
        if (request.uri.path.endsWith('/me')) {
          expect(
            request.headers['Authorization'] == 'Bearer ${tokens.accessToken}',
            isTrue,
          );
          return jsonResponse(success(identityJson()));
        }
        expect(request.uri.path, '/api/v1/auth/logout');
        expect(request.headers['Authorization'], isNull);
        expect(
          (request.data as Map)['refreshToken'] == tokens.refreshToken,
          isTrue,
        );
        return jsonResponse(success({'loggedOut': true}));
      });
      await api.currentUser(tokens.accessToken);
      await api.logout(tokens.refreshToken);
    },
  );
  for (final scenario in [
    (
      status: 401,
      code: 'INVALID_CREDENTIALS',
      kind: AuthFailureKind.invalidCredentials,
    ),
    (
      status: 401,
      code: 'INVALID_AUTHENTICATION',
      kind: AuthFailureKind.invalidSession,
    ),
    (status: 400, code: 'VALIDATION_ERROR', kind: AuthFailureKind.validation),
    (status: 429, code: 'RATE_LIMITED', kind: AuthFailureKind.rateLimited),
    (status: 500, code: 'INTERNAL_SERVER_ERROR', kind: AuthFailureKind.server),
  ]) {
    test('maps ${scenario.code} without exposing Dio exceptions', () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) =>
            jsonResponse(failureBody(scenario.code), status: scenario.status),
      );
      await expectLater(
        api.login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        ),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.kind,
            'kind',
            scenario.kind,
          ),
        ),
      );
    });
  }
  test('connection errors map to network failure', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      api.refresh(syntheticCredential()),
      throwsA(
        isA<AuthFailure>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.network,
        ),
      ),
    );
  });
  test('malformed response maps to unexpected response', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(success({})),
    );
    await expectLater(
      api.refresh(syntheticCredential()),
      throwsA(
        isA<AuthFailure>().having(
          (error) => error.kind,
          'kind',
          AuthFailureKind.unexpectedResponse,
        ),
      ),
    );
  });
}
