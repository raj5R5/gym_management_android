import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/providers/auth_providers.dart';

class DeletionRequest {
  const DeletionRequest({
    required this.id,
    required this.userId,
    required this.status,
    required this.requestedAt,
  });
  factory DeletionRequest.decode(Map data, String userId) {
    final id = data['id'];
    final status = data['status'];
    final date = DateTime.tryParse(
      data['requestedAt'] is String ? data['requestedAt'] as String : '',
    );
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(id) ||
        data['userId'] != userId ||
        !['requested', 'in_review', 'completed'].contains(status) ||
        date == null ||
        !date.isUtc) {
      throw const FormatException('Invalid deletion receipt.');
    }
    return DeletionRequest(
      id: id,
      userId: userId,
      status: status as String,
      requestedAt: date,
    );
  }
  final String id, userId, status;
  final DateTime requestedAt;
}

class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.message);
  final String message;
}

abstract interface class AccountDeletionRepository {
  Future<DeletionRequest?> status(String userId, CancelToken cancel);
  Future<DeletionRequest> request(
    String userId,
    String password,
    CancelToken cancel,
  );
}

class DioAccountDeletionRepository implements AccountDeletionRepository {
  DioAccountDeletionRepository(this.client);
  final Dio client;
  Future<DeletionRequest?> _read(
    String userId,
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final body = (await send()).data;
      if (body is! Map ||
          body['success'] != true ||
          body['data'] is! Map ||
          !(body['data'] as Map).containsKey('request')) {
        throw const FormatException();
      }
      final data = body['data']['request'];
      if (data == null) return null;
      if (data is! Map) throw const FormatException();
      return DeletionRequest.decode(data, userId);
    } on DioException catch (error) {
      final body = error.response?.data;
      final code = body is Map && body['error'] is Map
          ? body['error']['code']
          : null;
      throw AccountDeletionFailure(switch (code) {
        'ACCOUNT_DELETION_PASSWORD_INVALID' =>
          'Your current password is incorrect. No new request was saved.',
        'INVALID_AUTHENTICATION' =>
          'Sign in again to manage your account-deletion request.',
        'RATE_LIMITED' => 'Too many attempts. Please wait before trying again.',
        'NOT_FOUND' =>
          'Account-deletion requests are not available on this API yet. Use the public deletion page or contact support.',
        _ =>
          'The request status could not be confirmed. Check your connection and recheck the status before retrying.',
      });
    } on FormatException {
      throw const AccountDeletionFailure(
        'The server returned an invalid deletion receipt. Recheck the status or contact support.',
      );
    }
  }

  @override
  Future<DeletionRequest?> status(String userId, CancelToken cancel) => _read(
    userId,
    () => client.get<dynamic>(
      'auth/account-deletion-request',
      cancelToken: cancel,
    ),
  );

  @override
  Future<DeletionRequest> request(
    String userId,
    String password,
    CancelToken cancel,
  ) async {
    final receipt = await _read(
      userId,
      () => client.post<dynamic>(
        'auth/account-deletion-request',
        data: {
          'currentPassword': password,
          'acknowledgement': 'REQUEST_ACCOUNT_DELETION',
        },
        cancelToken: cancel,
      ),
    );
    if (receipt == null) {
      throw const AccountDeletionFailure(
        'The server did not confirm a saved request. Recheck its status.',
      );
    }
    return receipt;
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) =>
      DioAccountDeletionRepository(ref.watch(authenticatedApiClientProvider)),
);
final accountDeletionStatusProvider = FutureProvider.autoDispose
    .family<DeletionRequest?, String>((ref, userId) {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref
          .watch(accountDeletionRepositoryProvider)
          .status(userId, cancel);
    }, retry: (_, _) => null);
