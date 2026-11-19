import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class PasswordRecoveryFailure implements Exception {
  const PasswordRecoveryFailure(this.message);
  final String message;
}

abstract interface class PasswordRecoveryRepository {
  Future<void> request(String email, CancelToken cancel);
  Future<void> complete(String token, String password, CancelToken cancel);
}

final passwordRecoveryRepositoryProvider = Provider<PasswordRecoveryRepository>(
  (ref) => DioPasswordRecoveryRepository(ref.watch(apiClientProvider)),
);

class DioPasswordRecoveryRepository implements PasswordRecoveryRepository {
  DioPasswordRecoveryRepository(this.client);
  final Dio client;

  Future<void> _send(
    String path,
    Map<String, String> body,
    String confirmation,
    int status,
    CancelToken cancel,
  ) async {
    try {
      final response = await client.post<dynamic>(
        path,
        data: body,
        cancelToken: cancel,
        options: Options(
          followRedirects: false,
          headers: {'Authorization': null, 'Cookie': null, 'Origin': null},
          extra: {'authRequired': false},
        ),
      );
      final data = response.data;
      if (response.statusCode != status ||
          data is! Map ||
          data['success'] != true ||
          data['data'] is! Map ||
          data['data'][confirmation] != true) {
        throw const PasswordRecoveryFailure(
          'The server did not confirm this recovery step. Try signing in before retrying a password change.',
        );
      }
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map && data['error'] is Map
          ? data['error']['code']
          : null;
      throw PasswordRecoveryFailure(switch (code) {
        'INVALID_RECOVERY_CREDENTIAL' =>
          'The code is invalid or expired. Request a new code.',
        'RATE_LIMITED' => 'Too many attempts. Wait before trying again.',
        'PASSWORD_RECOVERY_UNAVAILABLE' =>
          'Recovery email delivery is unavailable. Retry later or contact support.',
        'VALIDATION_ERROR' =>
          'Check the email, code and password requirements.',
        _ when error.response?.statusCode == 404 =>
          'This server does not support account recovery yet. Contact support.',
        _ =>
          'Recovery could not be confirmed. Check your connection. If you submitted a new password, try signing in before repeating the change.',
      });
    }
  }

  @override
  Future<void> request(String email, CancelToken cancel) => _send(
    'auth/password-recovery/request',
    {'email': email.trim()},
    'accepted',
    202,
    cancel,
  );

  @override
  Future<void> complete(String token, String password, CancelToken cancel) =>
      _send(
        'auth/password-recovery/complete',
        {'token': token.trim(), 'newPassword': password},
        'passwordChanged',
        200,
        cancel,
      );
}
