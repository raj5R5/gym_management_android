import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public store/contact information only. Never put credentials in Dart defines.
class PublicAppInfo {
  const PublicAppInfo({
    this.appName = 'MuscleDesk',
    this.publisher = '',
    this.supportEmail = '',
    this.privacyUrl,
    this.deletionUrl,
  });

  factory PublicAppInfo.fromEnvironment() => PublicAppInfo.fromValues(
    appName: const String.fromEnvironment('PLAY_APP_NAME'),
    publisher: const String.fromEnvironment('PUBLISHER_NAME'),
    supportEmail: const String.fromEnvironment('SUPPORT_EMAIL'),
    privacyUrl: const String.fromEnvironment('PRIVACY_POLICY_URL'),
    deletionUrl: const String.fromEnvironment(
      'ACCOUNT_DELETION_URL',
      defaultValue: 'https://gym-api.semgroup.in/account-deletion',
    ),
    requireComplete: kReleaseMode,
  );

  factory PublicAppInfo.fromValues({
    String appName = '',
    String publisher = '',
    String supportEmail = '',
    String privacyUrl = '',
    String deletionUrl = '',
    bool requireComplete = false,
  }) {
    Uri? parse(String value) {
      if (value.isEmpty) return null;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException(
          'Public policy URLs must use HTTPS without credentials, queries or fragments.',
        );
      }
      return uri;
    }

    final privacy = parse(privacyUrl);
    final deletion = parse(deletionUrl);
    if (requireComplete &&
        (appName.trim().isEmpty ||
            publisher.trim().isEmpty ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(supportEmail) ||
            privacy == null ||
            deletion == null ||
            [privacy, deletion].any(
              (uri) => ['localhost', '127.0.0.1', '::1'].contains(uri.host),
            ) ||
            [appName, publisher, supportEmail, privacyUrl, deletionUrl].any(
              (value) => RegExp(
                r'replace|placeholder|example\.|\.invalid|\.test',
                caseSensitive: false,
              ).hasMatch(value),
            ))) {
      throw const FormatException(
        'Release requires final app/publisher/contact information and public privacy/deletion URLs.',
      );
    }
    return PublicAppInfo(
      appName: appName.trim().isEmpty ? 'MuscleDesk' : appName.trim(),
      publisher: publisher.trim(),
      supportEmail: supportEmail.trim(),
      privacyUrl: privacy,
      deletionUrl: deletion,
    );
  }

  final String appName, publisher, supportEmail;
  final Uri? privacyUrl, deletionUrl;
}

final publicAppInfoProvider = Provider<PublicAppInfo>(
  (_) => PublicAppInfo.fromEnvironment(),
);
