import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppEnvironment { development, staging, production }

/// Public build configuration only. Dart defines are not a secret store.
class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.isRelease,
  });

  factory AppConfig.fromEnvironment() {
    return AppConfig.fromValues(
      environmentName: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: kReleaseMode ? '' : 'development',
      ),
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
      isRelease: kReleaseMode,
    );
  }

  /// Allows tests to validate build settings without recompiling Dart defines.
  factory AppConfig.fromValues({
    String environmentName = 'development',
    String apiBaseUrl = '',
    bool isRelease = false,
  }) {
    final environment = switch (environmentName) {
      'development' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => throw const FormatException(
        'APP_ENV must be development, staging, or production. '
        'Release builds require an explicit APP_ENV.',
      ),
    };

    Uri? baseUrl;
    if (apiBaseUrl.isNotEmpty) {
      baseUrl = Uri.tryParse(apiBaseUrl);
      if (baseUrl == null ||
          !baseUrl.hasAuthority ||
          baseUrl.host.isEmpty ||
          !{'http', 'https'}.contains(baseUrl.scheme) ||
          baseUrl.userInfo.isNotEmpty ||
          baseUrl.hasQuery ||
          baseUrl.hasFragment) {
        throw const FormatException(
          'API_BASE_URL must be an absolute HTTP(S) URL without '
          'credentials, query parameters, or a fragment.',
        );
      }
      if (environment != AppEnvironment.development &&
          baseUrl.scheme != 'https') {
        throw const FormatException(
          'Staging and production require an HTTPS API_BASE_URL.',
        );
      }
      if (!baseUrl.path.endsWith('/')) {
        baseUrl = baseUrl.replace(path: '${baseUrl.path}/');
      }
    } else if (environment != AppEnvironment.development || isRelease) {
      throw const FormatException(
        'API_BASE_URL is required for staging, production, and release builds.',
      );
    }

    return AppConfig._(
      environment: environment,
      apiBaseUrl: baseUrl,
      isRelease: isRelease,
    );
  }

  final AppEnvironment environment;
  final Uri? apiBaseUrl;
  final bool isRelease;

  bool get developmentHomeEnabled =>
      environment == AppEnvironment.development && !isRelease;
}

final appConfigProvider = Provider<AppConfig>((ref) {
  throw StateError('AppConfig must be supplied by bootstrap.');
});
