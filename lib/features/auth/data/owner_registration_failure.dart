import 'package:dio/dio.dart';
import 'auth_failure.dart';

enum OwnerRegistrationFailureKind {
  duplicateEmail,
  duplicateGym,
  validation,
  rateLimited,
  unavailable,
  network,
  unexpected,
  configuration,
}

class OwnerRegistrationFailure implements Exception {
  const OwnerRegistrationFailure(this.kind);
  final OwnerRegistrationFailureKind kind;
  String get message => switch (kind) {
    OwnerRegistrationFailureKind.duplicateEmail =>
      'An account already uses this email. Sign in instead.',
    OwnerRegistrationFailureKind.duplicateGym =>
      'A gym with this name already exists. Choose a different name.',
    OwnerRegistrationFailureKind.validation =>
      'Check the registration fields and password requirements.',
    OwnerRegistrationFailureKind.rateLimited =>
      'Too many sign-up attempts. Please try again later.',
    OwnerRegistrationFailureKind.configuration =>
      'The API connection is not configured.',
    OwnerRegistrationFailureKind.unavailable =>
      'Registration is temporarily unavailable. Please try again later.',
    OwnerRegistrationFailureKind.network =>
      'Unable to confirm registration. Check your connection. If your account was created, you can sign in normally.',
    OwnerRegistrationFailureKind.unexpected =>
      'Unable to confirm registration. If your account was created, you can sign in normally.',
  };
  String? fieldError(String field) => switch ((kind, field)) {
    (OwnerRegistrationFailureKind.duplicateEmail, 'email') => message,
    (OwnerRegistrationFailureKind.duplicateGym, 'gymName') => message,
    _ => null,
  };
  static OwnerRegistrationFailure fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    final status = error.response?.statusCode;
    if (status == 409 && code == 'DUPLICATE_EMAIL') {
      return const OwnerRegistrationFailure(
        OwnerRegistrationFailureKind.duplicateEmail,
      );
    }
    if (status == 409 && code == 'DUPLICATE_GYM_NAME') {
      return const OwnerRegistrationFailure(
        OwnerRegistrationFailureKind.duplicateGym,
      );
    }
    if (status == 503 && code == 'OWNER_REGISTRATION_STORAGE_UNAVAILABLE') {
      return const OwnerRegistrationFailure(
        OwnerRegistrationFailureKind.unavailable,
      );
    }
    final auth = AuthFailure.fromDio(error);
    return OwnerRegistrationFailure(switch (auth.kind) {
      AuthFailureKind.validation => OwnerRegistrationFailureKind.validation,
      AuthFailureKind.rateLimited => OwnerRegistrationFailureKind.rateLimited,
      AuthFailureKind.network => OwnerRegistrationFailureKind.network,
      AuthFailureKind.configuration =>
        OwnerRegistrationFailureKind.configuration,
      _ => OwnerRegistrationFailureKind.unexpected,
    });
  }

  @override
  String toString() => 'OwnerRegistrationFailure(${kind.name}): $message';
}
