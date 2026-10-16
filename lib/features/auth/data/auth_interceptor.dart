import 'dart:convert';
import 'package:dio/dio.dart';

import 'auth_failure.dart';
import 'auth_repository.dart';

/// Add only to the authenticated client; auth endpoints use the public client.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required Dio client, required AuthRepository repository})
    : _client = client,
      _repository = repository;
  final Dio _client;
  final AuthRepository _repository;
  static const _retried = 'authRetried';
  static const _revision = 'authRevision';

  bool _public(RequestOptions options) {
    final base = Uri.parse(_client.options.baseUrl);
    return options.extra['authRequired'] == false ||
        [
          'auth/login',
          'auth/refresh',
          'auth/logout',
        ].any((path) => options.uri.path == base.resolve(path).path);
  }

  DioException _reject(RequestOptions options, AuthFailure failure) =>
      DioException(
        requestOptions: options,
        error: failure,
        message: failure.message,
      );

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Transport redirects bypass interceptors. Enforce this even when callers
    // explicitly request redirects; bearer credentials stay at the checked URL.
    options.followRedirects = false;
    if (_public(options)) {
      options.headers.removeWhere(
        (key, _) => key.toLowerCase() == 'authorization',
      );
      handler.next(options);
      return;
    }
    final base = Uri.parse(_client.options.baseUrl);
    if (options.uri.origin != base.origin ||
        !options.uri.path.startsWith(base.path)) {
      handler.reject(
        _reject(options, const AuthFailure(AuthFailureKind.configuration)),
      );
      return;
    }
    if (options.extra[_retried] == true &&
        options.extra[_revision] != _repository.revision) {
      handler.reject(
        _reject(options, const AuthFailure(AuthFailureKind.invalidSession)),
      );
      return;
    }
    final revision = _repository.revision;
    try {
      // New protected requests also wait instead of using a staged session or
      // failing merely because another request is recovering the session.
      final pending = _repository.pendingRecovery;
      if (pending != null) await pending;
      final token = _repository.accessToken;
      if (revision != _repository.revision || token == null) {
        throw const AuthFailure(AuthFailureKind.invalidSession);
      }
      options.headers.removeWhere(
        (key, _) => key.toLowerCase() == 'authorization',
      );
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[_revision] = revision;
      handler.next(options);
    } on AuthFailure catch (failure) {
      handler.reject(_reject(options, failure));
    } catch (_) {
      handler.reject(
        _reject(options, const AuthFailure(AuthFailureKind.unexpectedResponse)),
      );
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final error = err;
    final options = error.requestOptions;
    // Authenticated image downloads use byte responses. Decode only JSON
    // error envelopes so the existing refresh/scope/replay safeguards apply.
    if (options.responseType == ResponseType.bytes &&
        error.response?.data is List<int> &&
        (error.response?.headers
                .value('content-type')
                ?.contains('application/json') ??
            false)) {
      try {
        error.response!.data = jsonDecode(
          utf8.decode(error.response!.data as List<int>),
        );
      } catch (_) {
        // An invalid envelope cannot establish an authentication failure.
      }
    }
    final data = error.response?.data;
    final invalidSession =
        error.response?.statusCode == 401 &&
        data is Map &&
        data['error'] is Map &&
        (data['error'] as Map)['code'] == 'INVALID_AUTHENTICATION';
    if (!invalidSession || _public(options)) {
      handler.next(error);
      return;
    }
    try {
      if (options.extra[_revision] != _repository.revision) {
        throw const AuthFailure(AuthFailureKind.invalidSession);
      }
      if (options.extra[_retried] == true) {
        await _repository.invalidateSession();
        throw const AuthFailure(AuthFailureKind.invalidSession);
      }
      final sentToken = options.headers['Authorization'];
      final currentToken = _repository.accessToken;
      final pending = _repository.pendingRecovery;
      // A late 401 for the old token must not rotate the new credential again.
      if (pending != null) {
        await pending;
      } else if (currentToken == null || sentToken == 'Bearer $currentToken') {
        await _repository.refreshSession();
      }
      if (options.extra[_revision] != _repository.revision ||
          _repository.accessToken == null) {
        throw const AuthFailure(AuthFailureKind.invalidSession);
      }
      // Streams and multipart bodies are not safely replayable automatically.
      if (options.data is Stream || options.data is FormData) {
        throw const AuthFailure(AuthFailureKind.retryRequired);
      }
      options.extra[_retried] = true;
      handler.resolve(await _client.fetch<dynamic>(options));
    } on AuthFailure catch (failure) {
      handler.reject(_reject(options, failure));
    } on DioException catch (retryError) {
      handler.reject(retryError);
    } catch (_) {
      handler.reject(
        _reject(options, const AuthFailure(AuthFailureKind.unexpectedResponse)),
      );
    }
  }
}
