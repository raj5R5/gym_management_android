import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

String credentialStorageNamespace(AppConfig config) =>
    'gym.auth.${config.environment.name}.'
    '${Uri.encodeComponent(config.apiBaseUrl?.toString() ?? 'unconfigured')}';

class CredentialStorageFailure implements Exception {
  const CredentialStorageFailure();
  @override
  String toString() => 'Secure credential storage is unavailable.';
}

abstract interface class CredentialStorage {
  Future<String?> readRefreshCredential();
  Future<void> writeRefreshCredential(String credential);
  Future<void> clearRefreshCredential();
}

/// Only the rotating refresh credential is persisted, in a single scoped key.
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage({
    required FlutterSecureStorage storage,
    required String namespace,
  }) : _storage = storage,
       _key = '$namespace.refresh';

  final FlutterSecureStorage _storage;
  final String _key;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      // Platform exceptions can contain sensitive implementation details.
      throw const CredentialStorageFailure();
    }
  }

  @override
  Future<String?> readRefreshCredential() =>
      _guard(() => _storage.read(key: _key));
  @override
  Future<void> writeRefreshCredential(String credential) =>
      _guard(() => _storage.write(key: _key, value: credential));
  @override
  Future<void> clearRefreshCredential() =>
      _guard(() => _storage.delete(key: _key));
}
