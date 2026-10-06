import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Infrastructure for future API services. Creating it sends no request.
/// Services should use relative endpoint paths to preserve the API base path.
Dio createApiClient(AppConfig config) {
  final client = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl?.toString() ?? '',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
    ),
  );
  // Development runs without a backend, but unconfigured requests fail clearly.
  client.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (config.apiBaseUrl == null) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: StateError('API_BASE_URL is not configured.'),
              message: 'Configure API_BASE_URL before using the API client.',
            ),
          );
          return;
        }
        handler.next(options);
      },
    ),
  );
  return client;
}

final apiClientProvider = Provider<Dio>((ref) {
  final client = createApiClient(ref.watch(appConfigProvider));
  ref.onDispose(() => client.close(force: true));
  return client;
});
