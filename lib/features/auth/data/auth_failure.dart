import 'package:dio/dio.dart';

enum AuthFailureKind {
  invalidCredentials,
  invalidSession,
  network,
  server,
  unexpectedResponse,
  validation,
  rateLimited,
  locked,
  forbidden,
  storage,
  configuration,
  retryRequired,
}

class AuthFailure implements Exception {
  const AuthFailure(
    this.kind, {
    this.statusCode,
    this.transportType,
    this.requestId,
  });
  final AuthFailureKind kind;
  final int? statusCode;
  final DioExceptionType? transportType;
  final String? requestId;

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
    AuthFailureKind.locked =>
      'Too many wrong passwords. Wait 15 minutes, or use Recover access.',
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
    final meta = data is Map ? data['meta'] : null;
    final id = meta is Map ? meta['requestId'] : null;
    AuthFailure failure(AuthFailureKind kind) => AuthFailure(
      kind,
      statusCode: error.response?.statusCode,
      transportType: error.type,
      requestId: id is String ? id : null,
    );
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    if (error.response?.statusCode == 401 && code == 'INVALID_CREDENTIALS') {
      return failure(AuthFailureKind.invalidCredentials);
    }
    if (error.response?.statusCode == 401 && code == 'INVALID_AUTHENTICATION') {
      return failure(AuthFailureKind.invalidSession);
    }
    final status = error.response?.statusCode;
    if (status == 400) return failure(AuthFailureKind.validation);
    if (status == 403) return failure(AuthFailureKind.forbidden);
    if (status == 429 && code == 'ACCOUNT_TEMPORARILY_LOCKED') {
      return failure(AuthFailureKind.locked);
    }
    if (status == 429) return failure(AuthFailureKind.rateLimited);
    if (status != null && status >= 500) {
      return failure(AuthFailureKind.server);
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.badCertificate) {
      return failure(AuthFailureKind.network);
    }
    if (error.error is StateError && error.response == null) {
      return failure(AuthFailureKind.configuration);
    }
    return failure(AuthFailureKind.unexpectedResponse);
  }

  @override
  String toString() => 'AuthFailure(${kind.name}): $message';
}
