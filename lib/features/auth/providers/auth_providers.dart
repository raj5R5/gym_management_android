import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/credential_storage.dart';
import '../data/auth_api_service.dart';
import '../data/auth_interceptor.dart';
import '../data/auth_operation_queue.dart';
import '../data/auth_repository.dart';

final credentialStorageProvider = Provider<CredentialStorage>((ref) {
  final config = ref.watch(appConfigProvider);
  return SecureCredentialStorage(
    storage: const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
    namespace: credentialStorageNamespace(config),
  );
});

final authApiServiceProvider = Provider<AuthApiService>(
  (ref) => DioAuthApiService(ref.watch(apiClientProvider)),
);

// Intentionally independent of configuration and API dependencies so this queue
// outlives repositories recreated within the same ProviderContainer.
final authOperationQueueProvider = Provider<AuthOperationQueue>(
  (ref) => AuthOperationQueue(),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = AuthRepository(
    api: ref.watch(authApiServiceProvider),
    storage: ref.watch(credentialStorageProvider),
    operationQueue: ref.watch(authOperationQueueProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Future protected API services should use this provider, not the public client.
final authenticatedApiClientProvider = Provider<Dio>((ref) {
  final client = createApiClient(ref.watch(appConfigProvider));
  client.options.followRedirects = false;
  client.interceptors.add(
    AuthInterceptor(
      client: client,
      repository: ref.watch(authRepositoryProvider),
    ),
  );
  ref.onDispose(() => client.close(force: true));
  return client;
});
