import 'package:dio/dio.dart';

enum AuthFailureKind {
  invalidCredentials,
  invalidSession,
  network,
  server,
  unexpectedResponse,
  validation,
  rateLimited,
  forbidden,
  storage,
  configuration,
  retryRequired,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind);
  final AuthFailureKind kind;

  String get message => switch (kind) {
    AuthFailureKind.invalidCredentials => 'Invalid email or password.',
    AuthFailureKind.invalidSession =>
      'Your session is invalid or expired. Sign in again.',
    AuthFailureKind.network =>
      'Unable to reach the server. Check your connection.',
    AuthFailureKind.server => 'The service is temporarily unavailable.',
    AuthFailureKind.unexpectedResponse =>
      'The server returned an unexpected response.',
    AuthFailureKind.validation => 'Check the supplied information.',
    AuthFailureKind.rateLimited => 'Too many requests. Try again later.',
    AuthFailureKind.forbidden => 'This action is not permitted.',
    AuthFailureKind.storage =>
      'Authentication credentials could not be securely stored or cleared.',
    AuthFailureKind.configuration => 'The API connection is not configured.',
    AuthFailureKind.retryRequired =>
      'Your session was recovered. Retry this action.',
  };

  static AuthFailure fromDio(DioException error) {
    if (error.error case final AuthFailure failure) return failure;
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    if (error.response?.statusCode == 401 && code == 'INVALID_CREDENTIALS') {
      return const AuthFailure(AuthFailureKind.invalidCredentials);
    }
    if (error.response?.statusCode == 401 && code == 'INVALID_AUTHENTICATION') {
      return const AuthFailure(AuthFailureKind.invalidSession);
    }
    final status = error.response?.statusCode;
    if (status == 400) return const AuthFailure(AuthFailureKind.validation);
    if (status == 403) return const AuthFailure(AuthFailureKind.forbidden);
    if (status == 429) return const AuthFailure(AuthFailureKind.rateLimited);
    if (status != null && status >= 500) {
      return const AuthFailure(AuthFailureKind.server);
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.badCertificate) {
      return const AuthFailure(AuthFailureKind.network);
    }
    if (error.error is StateError && error.response == null) {
      return const AuthFailure(AuthFailureKind.configuration);
    }
    return const AuthFailure(AuthFailureKind.unexpectedResponse);
  }

  @override
  String toString() => 'AuthFailure(${kind.name}): $message';
}
