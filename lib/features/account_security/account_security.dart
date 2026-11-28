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
        'VALIDATION_ERROR' => 'Use a password of 1–128 characters.',
        'INVALID_VERIFICATION_CODE' =>
          'That code is not correct or has expired. Send a new code.',
        'EMAIL_ALREADY_VERIFIED' => 'Your email is already verified.',
        'EMAIL_DELIVERY_UNAVAILABLE' =>
          'Email could not be sent right now. Try again later.',
        'RATE_LIMITED' => 'Too many tries. Wait a few minutes.',
        'INVALID_OTP' => 'That code is not correct or has expired.',
        'OTP_RESEND_TOO_SOON' =>
          'Wait a minute before asking for another code.',
        'OTP_LIMIT_REACHED' =>
          'Too many codes for this number. Try again in an hour.',
        'OTP_DELIVERY_UNAVAILABLE' =>
          'The code could not be sent right now. Try again later.',
        'PHONE_ALREADY_REGISTERED' =>
          'This number is already used by another account.',
        'PHONE_NOT_VERIFIED' => 'Add and verify a phone number first.',
        'EMAIL_NOT_SET' => 'Add an email address first.',
        'PASSWORD_NOT_SET' => 'This account signs in with a phone code.',
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

  /// Sends a code to a new number for this account.
  Future<void> requestPhoneCode(String digits) => _call(
    () =>
        _client.post<dynamic>('account/phone/request', data: {'phone': digits}),
    (_) {},
  );

  /// Sets the account's phone once the code is right.
  Future<void> confirmPhone(String digits, String code) => _call(
    () => _client.post<dynamic>(
      'account/phone/confirm',
      data: {'phone': digits, 'code': code},
    ),
    (_) {},
  );

  /// Sends a code to the account's own phone, to confirm a sensitive change
  /// when the account has no password.
  Future<void> sendConfirmCode() => _call(
    () =>
        _client.post<dynamic>('account/confirm-code', data: <String, Object>{}),
    (_) {},
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
