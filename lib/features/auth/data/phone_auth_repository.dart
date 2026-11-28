import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/auth_models.dart';
import 'auth_failure.dart';

/// The 10 digits of an Indian mobile however it is typed, or null.
/// Mirrors the backend's phone.js; the server checks again.
String? indianMobileDigits(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text.length > 25 ||
      !RegExp(r'^[+0-9 ()-]+$').hasMatch(text) ||
      '+'.allMatches(text).length > 1) {
    return null;
  }
  var digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits) ? digits : null;
}

String? validateIndianMobile(String? value) =>
    indianMobileDigits(value ?? '') == null
    ? 'Enter a 10-digit mobile number.'
    : null;

class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure(this.message, {this.retryAfterSeconds, this.code});
  final String message;
  final int? retryAfterSeconds;
  final String? code;

  factory PhoneAuthFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final failure = data is Map ? data['error'] : null;
    final code = failure is Map ? failure['code'] as String? : null;
    final details = failure is Map ? failure['details'] : null;
    final retry = details is Map ? details['retryAfterSeconds'] : null;
    final wait = retry is int ? retry : null;
    String inMinutes(int seconds) =>
        seconds < 90 ? '$seconds seconds' : '${(seconds / 60).ceil()} minutes';
    final message = switch (code) {
      'INVALID_OTP' => 'That code is not correct or has expired.',
      'OTP_RESEND_TOO_SOON' =>
        'Wait ${inMinutes(wait ?? 60)} before asking for another code.',
      'OTP_LIMIT_REACHED' =>
        'Too many codes for this number. Try again in ${inMinutes(wait ?? 3600)}.',
      'OTP_DELIVERY_UNAVAILABLE' =>
        'The code could not be sent right now. Try again later, or sign in with email.',
      'SIGNUP_TICKET_INVALID' =>
        'That took too long. Verify your number again to continue.',
      'PHONE_ALREADY_REGISTERED' =>
        'This number already has an account. Sign in with it instead.',
      'DUPLICATE_GYM_NAME' =>
        'A gym with this name already exists. Add your area to the name.',
      'DUPLICATE_EMAIL' =>
        'This email is used by another account. Leave it empty or use another.',
      'VALIDATION_ERROR' => 'Check the details and try again.',
      _ => AuthFailure.fromDio(error).message,
    };
    return PhoneAuthFailure(message, retryAfterSeconds: wait, code: code);
  }

  @override
  String toString() => 'PhoneAuthFailure: $message';
}

class PhoneCodeSent {
  const PhoneCodeSent({required this.resendAfter});
  final Duration resendAfter;
}

/// What a correct code leads to.
sealed class PhoneVerification {
  const PhoneVerification();
}

/// The number belongs to an account: these are its new session credentials.
class PhoneSignedIn extends PhoneVerification {
  const PhoneSignedIn(this.response);
  final LoginResponse response;
}

/// A new number: the ticket lets this person create an account for it.
class PhoneNewAccount extends PhoneVerification {
  const PhoneNewAccount({required this.signupToken, required this.phone});
  final String signupToken;
  final String phone;
}

/// Public phone sign-in calls. No stored credentials are sent; the session is
/// stored only after the server answers, through the session controller.
class PhoneAuthRepository {
  PhoneAuthRepository(this._client);
  final Dio _client;

  static final _public = Options(
    followRedirects: false,
    responseType: ResponseType.json,
    headers: {'Authorization': null, 'Cookie': null, 'Origin': null},
    extra: {'authRequired': false},
  );

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    try {
      final response = await _client.post<dynamic>(
        path,
        data: body,
        options: _public,
      );
      final data = response.data;
      if (data is! Map ||
          data['success'] != true ||
          data['data'] is! Map<String, dynamic>) {
        throw const PhoneAuthFailure(
          'The server returned an unexpected response.',
        );
      }
      return data['data'] as Map<String, dynamic>;
    } on DioException catch (error) {
      throw PhoneAuthFailure.fromDio(error);
    }
  }

  Future<PhoneCodeSent> requestCode(String digits) async {
    final data = await _post('auth/otp/request', {'phone': digits});
    final wait = data['resendAfterSeconds'];
    return PhoneCodeSent(
      resendAfter: Duration(seconds: wait is int ? wait : 60),
    );
  }

  Future<PhoneVerification> verify(String digits, String code) async {
    final data = await _post('auth/otp/verify', {
      'phone': digits,
      'code': code,
      'client': 'mobile',
    });
    try {
      return switch (data['status']) {
        'signed_in' => PhoneSignedIn(LoginResponse.fromJson(data)),
        'new_account' => PhoneNewAccount(
          signupToken: data['signupToken'] as String,
          phone: data['phone'] as String,
        ),
        _ => throw const FormatException('Unknown phone sign-in result.'),
      };
    } on FormatException {
      throw const PhoneAuthFailure(
        'The server returned an unexpected response.',
      );
    } on TypeError {
      throw const PhoneAuthFailure(
        'The server returned an unexpected response.',
      );
    }
  }

  /// Creates the owner account and gym for a verified new number.
  Future<LoginResponse> registerOwner({
    required String signupToken,
    required String ownerFullName,
    required String gymName,
    String? email,
  }) async {
    final data = await _post('auth/phone/register-owner', {
      'signupToken': signupToken,
      'ownerFullName': ownerFullName.trim(),
      'gymName': gymName.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      'client': 'mobile',
    });
    try {
      return LoginResponse.fromJson(data);
    } on FormatException {
      throw const PhoneAuthFailure(
        'The server returned an unexpected response.',
      );
    }
  }
}

final phoneAuthRepositoryProvider = Provider<PhoneAuthRepository>(
  (ref) => PhoneAuthRepository(ref.watch(apiClientProvider)),
);
