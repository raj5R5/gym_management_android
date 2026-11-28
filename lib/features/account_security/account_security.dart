import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

class SignedInDevice {
  SignedInDevice.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      clientType = json['clientType'] as String,
      current = json['current'] == true,
      lastUsedAt = DateTime.parse(json['lastUsedAt'] as String).toLocal(),
      signedInAt = DateTime.parse(json['signedInAt'] as String).toLocal();
  final String id, clientType;
  final bool current;
  final DateTime lastUsedAt, signedInAt;
}

class AccountSecurityFailure implements Exception {
  const AccountSecurityFailure(this.message);
  final String message;
  @override
  String toString() => 'AccountSecurityFailure: $message';
}

/// Signed-in account protection: password, devices and email verification.
class AccountSecurityRepository {
  AccountSecurityRepository(this._client);
  final Dio _client;

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const AccountSecurityFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw AccountSecurityFailure(switch (code) {
        'CURRENT_PASSWORD_INCORRECT' => 'Your current password is not correct.',
        'PASSWORD_UNCHANGED' =>
          'Choose a password different from your current one.',
        'VALIDATION_ERROR' =>
          'Use 15–128 characters and avoid common passwords.',
        'INVALID_VERIFICATION_CODE' =>
          'That code is not correct or has expired. Send a new code.',
        'EMAIL_ALREADY_VERIFIED' => 'Your email is already verified.',
        'EMAIL_DELIVERY_UNAVAILABLE' =>
          'Email could not be sent right now. Try again later.',
        'RATE_LIMITED' => 'Too many tries. Wait a few minutes.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const AccountSecurityFailure(
        'The server returned unexpected data.',
      );
    }
  }

  /// Returns how many other devices were signed out.
  Future<int> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _call(
    () => _client.post<dynamic>(
      'account/password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    ),
    (data) => (data as Map)['otherSessionsEnded'] as int,
  );

  Future<List<SignedInDevice>> devices() => _call(
    () => _client.get<dynamic>('account/sessions'),
    (data) => [
      for (final row in data as List)
        SignedInDevice.fromJson(row as Map<String, dynamic>),
    ],
  );

  Future<int> signOutOthers() => _call(
    () => _client.post<dynamic>('account/sessions/sign-out-others'),
    (data) => (data as Map)['otherSessionsEnded'] as int,
  );

  Future<void> sendVerification() =>
      _call(() => _client.post<dynamic>('account/email-verification'), (_) {});

  Future<void> confirmVerification(String code) => _call(
    () => _client.post<dynamic>(
      'account/email-verification/confirm',
      data: {'code': code},
    ),
    (_) {},
  );
}

final accountSecurityRepositoryProvider = Provider<AccountSecurityRepository>(
  (ref) => AccountSecurityRepository(ref.watch(authenticatedApiClientProvider)),
);

final signedInDevicesProvider =
    FutureProvider.autoDispose<List<SignedInDevice>>(
      (ref) => ref.watch(accountSecurityRepositoryProvider).devices(),
      retry: (_, _) => null,
    );
