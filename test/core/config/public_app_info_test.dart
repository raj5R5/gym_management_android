import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/public_app_info.dart';

void main() {
  test(
    'default build exposes the approved deletion page without fake contacts',
    () {
      final info = PublicAppInfo.fromEnvironment();
      expect(
        info.deletionUrl.toString(),
        'https://gym-api.semgroup.in/account-deletion',
      );
      expect(info.supportEmail, isEmpty);
      expect(info.publisher, isEmpty);
      expect(info.privacyUrl, isNull);
    },
  );

  PublicAppInfo release({String privacy = 'https://gym-company.com/privacy'}) =>
      PublicAppInfo.fromValues(
        appName: 'Gym Operations',
        publisher: 'Gym Company',
        supportEmail: 'support@gym-company.com',
        privacyUrl: privacy,
        deletionUrl: 'https://gym-company.com/delete-account',
        requireComplete: true,
      );
  test('development explains missing details without inventing contacts', () {
    final info = PublicAppInfo.fromValues();
    expect(info.privacyUrl, isNull);
    expect(info.supportEmail, isEmpty);
  });
  test('release accepts complete public information', () {
    expect(release().privacyUrl.toString(), 'https://gym-company.com/privacy');
  });
  test('release blocks missing or placeholder public information', () {
    expect(
      () => PublicAppInfo.fromValues(requireComplete: true),
      throwsFormatException,
    );
    expect(
      () => release(privacy: 'https://example.test/privacy'),
      throwsFormatException,
    );
  });
  for (final uri in [
    'http://gym-company.com/privacy',
    'https://user:secret@gym-company.com/privacy',
    '/privacy',
    'https://gym-company.com/privacy?token=secret',
  ]) {
    test(
      'unsafe public URL is rejected: $uri',
      () => expect(() => release(privacy: uri), throwsFormatException),
    );
  }
}
