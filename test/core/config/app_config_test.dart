import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';

void main() {
  test('development can run without a backend', () {
    final config = AppConfig.fromValues();
    expect(config.environment, AppEnvironment.development);
    expect(config.apiBaseUrl, isNull);
    expect(config.developmentHomeEnabled, isTrue);
  });

  test('unknown environment fails rather than falling back to development', () {
    expect(
      () => AppConfig.fromValues(environmentName: 'prod'),
      throwsFormatException,
    );
  });

  test('release requires an explicit valid environment', () {
    expect(
      () => AppConfig.fromValues(environmentName: '', isRelease: true),
      throwsFormatException,
    );
  });

  for (final environment in ['staging', 'production']) {
    test('$environment requires an API URL', () {
      expect(
        () => AppConfig.fromValues(environmentName: environment),
        throwsFormatException,
      );
    });

    test('$environment rejects insecure transport', () {
      expect(
        () => AppConfig.fromValues(
          environmentName: environment,
          apiBaseUrl: 'http://api.example.test',
        ),
        throwsFormatException,
      );
    });
  }

  test('release requires an API URL even with development selected', () {
    expect(() => AppConfig.fromValues(isRelease: true), throwsFormatException);
  });

  for (final environment in ['development', 'staging']) {
    test('release rejects $environment even with the production API', () {
      expect(
        () => AppConfig.fromValues(
          environmentName: environment,
          apiBaseUrl: AppConfig.productionApiBaseUrl,
          isRelease: true,
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'release uses the approved production API without development routes',
    () {
      final config = AppConfig.fromValues(
        environmentName: 'production',
        apiBaseUrl: AppConfig.productionApiBaseUrl,
        isRelease: true,
      );
      expect(config.apiBaseUrl.toString(), AppConfig.productionApiBaseUrl);
      expect(config.developmentHomeEnabled, isFalse);
    },
  );

  for (final url in [
    'https://staging.gym-company.com/api/v1/',
    'https://gym-api.semgroup.in/',
    'https://gym-api.semgroup.in/api/v2/',
    'http://gym-api.semgroup.in/api/v1/',
    'https://localhost/api/v1/',
  ]) {
    test('release rejects an unapproved API: $url', () {
      expect(
        () => AppConfig.fromValues(
          environmentName: 'production',
          apiBaseUrl: url,
          isRelease: true,
        ),
        throwsFormatException,
      );
    });
  }

  for (final url in [
    '/api',
    'not a URL',
    'https://',
    'ftp://api.example.test',
    'https://user:password@api.example.test',
    'https://api.example.test?key=value',
    'https://api.example.test#fragment',
  ]) {
    test('rejects invalid or credential-bearing base URL: $url', () {
      expect(
        () => AppConfig.fromValues(apiBaseUrl: url),
        throwsFormatException,
      );
    });
  }

  test('normalizes the base path without losing its prefix', () {
    final config = AppConfig.fromValues(
      apiBaseUrl: 'https://api.example.test/api/v1',
    );
    expect(config.apiBaseUrl.toString(), 'https://api.example.test/api/v1/');
  });

  test('development supports an explicit local HTTP endpoint', () {
    final config = AppConfig.fromValues(apiBaseUrl: 'http://localhost:3000');
    expect(config.apiBaseUrl.toString(), 'http://localhost:3000/');
  });
}
