import 'package:dio/dio.dart';

import '../models/auth_models.dart';
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
  DioAuthApiService(this._client);
  final Dio _client;

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
    Future<Response<dynamic>> Function() request,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final response = await request();
      final body = response.data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const AuthFailure(AuthFailureKind.unexpectedResponse);
      }
      return decode(body['data'] as Map<String, dynamic>);
    } on AuthFailure {
      rethrow;
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.unexpectedResponse);
    }
  }

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) => _request(
    () => _client.post<dynamic>(
      'auth/login',
      data: {'email': email.trim(), 'password': password, 'client': 'mobile'},
      options: _options(),
    ),
    LoginResponse.fromJson,
  );

  @override
  Future<AuthTokens> refresh(String refreshCredential) => _request(
    () => _client.post<dynamic>(
      'auth/refresh',
      data: {'refreshToken': refreshCredential},
      options: _options(),
    ),
    AuthTokens.fromJson,
  );

  @override
  Future<AuthIdentity> currentUser(String accessToken) => _request(
    () => _client.get<dynamic>(
      'auth/me',
      options: _options(accessToken: accessToken),
    ),
    AuthIdentity.fromJson,
  );

  @override
  Future<void> logout(String refreshCredential) => _request(
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
