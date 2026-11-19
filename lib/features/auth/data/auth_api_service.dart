import 'package:dio/dio.dart';

import '../models/auth_models.dart';
import 'auth_diagnostics.dart';
import 'auth_failure.dart';

abstract interface class AuthApiService {
  Future<LoginResponse> login({
    required String email,
    required String password,
  });
  Future<AuthTokens> refresh(String refreshCredential);
  Future<AuthIdentity> currentUser(String accessToken);
  Future<void> logout(String refreshCredential);
}

/// Mobile JSON transport: no cookies, Origin header, or automatic retries.
class DioAuthApiService implements AuthApiService {
  DioAuthApiService(
    this._client, {
    AuthDiagnostics diagnostics = const AuthDiagnostics(),
  }) : _diagnostics = diagnostics;
  final Dio _client;
  final AuthDiagnostics _diagnostics;

  Options _options({String? accessToken}) => Options(
    responseType: ResponseType.json,
    followRedirects: false,
    headers: {
      'Authorization': accessToken == null ? null : 'Bearer $accessToken',
      'Origin': null,
      'Cookie': null,
    },
    extra: {'authRequired': false},
  );

  Future<T> _request<T>(
    AuthStage stage,
    Future<Response<dynamic>> Function() request,
    T Function(Map<String, dynamic>) decode,
  ) async {
    final watch = Stopwatch()..start();
    Response<dynamic>? response;
    _diagnostics.record(stage, AuthEvent.started);
    String? requestId() {
      final body = response?.data;
      final meta = body is Map ? body['meta'] : null;
      final id = meta is Map ? meta['requestId'] : null;
      return id is String ? id : null;
    }

    try {
      response = await request();
      final body = response.data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const AuthFailure(AuthFailureKind.unexpectedResponse);
      }
      final result = decode(body['data'] as Map<String, dynamic>);
      _diagnostics.record(
        stage,
        AuthEvent.succeeded,
        statusCode: response.statusCode,
        requestId: requestId(),
        elapsedMs: watch.elapsedMilliseconds,
      );
      return result;
    } catch (error) {
      final failure = switch (error) {
        DioException error => AuthFailure.fromDio(error),
        AuthFailure error => AuthFailure(
          error.kind,
          statusCode: error.statusCode ?? response?.statusCode,
          transportType: error.transportType,
          requestId: error.requestId ?? requestId(),
        ),
        _ => AuthFailure(
          AuthFailureKind.unexpectedResponse,
          statusCode: response?.statusCode,
          requestId: requestId(),
        ),
      };
      _diagnostics.record(
        stage,
        AuthEvent.failed,
        failure: failure,
        elapsedMs: watch.elapsedMilliseconds,
      );
      throw failure;
    }
  }

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) => _request(
    AuthStage.loginApi,
    () => _client.post<dynamic>(
      'auth/login',
      data: {'email': email.trim(), 'password': password, 'client': 'mobile'},
      options: _options(),
    ),
    LoginResponse.fromJson,
  );

  @override
  Future<AuthTokens> refresh(String refreshCredential) => _request(
    AuthStage.refreshApi,
    () => _client.post<dynamic>(
      'auth/refresh',
      data: {'refreshToken': refreshCredential},
      options: _options(),
    ),
    AuthTokens.fromJson,
  );

  @override
  Future<AuthIdentity> currentUser(String accessToken) => _request(
    AuthStage.currentUserApi,
    () => _client.get<dynamic>(
      'auth/me',
      options: _options(accessToken: accessToken),
    ),
    AuthIdentity.fromJson,
  );

  @override
  Future<void> logout(String refreshCredential) => _request(
    AuthStage.logoutApi,
    () => _client.post<dynamic>(
      'auth/logout',
      data: {'refreshToken': refreshCredential},
      options: _options(),
    ),
    (data) {
      if (data['loggedOut'] != true) {
        throw const AuthFailure(AuthFailureKind.unexpectedResponse);
      }
    },
  );
}
