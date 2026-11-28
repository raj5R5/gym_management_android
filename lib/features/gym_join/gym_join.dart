import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

enum JoinRole {
  member('member', 'Member'),
  trainer('trainer', 'Trainer');

  const JoinRole(this.wire, this.label);
  final String wire, label;

  static JoinRole from(Object? value) =>
      values.firstWhere((role) => role.wire == value, orElse: () => member);
}

enum JoinStatus { pending, approved, rejected, cancelled }

/// Someone asking a gym to let them in, as the gym or the asker sees it.
class JoinRequest {
  JoinRequest.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      gymId = json['gymId'] as String,
      gymName = json['gymName'] as String?,
      role = JoinRole.from(json['role']),
      name = json['name'] as String,
      phone = json['phone'] as String,
      status = JoinStatus.values.byName(json['status'] as String),
      createdAt = DateTime.parse(json['createdAt'] as String).toLocal(),
      reason = json['reason'] as String?;
  final String id, gymId, name, phone;
  final String? gymName, reason;
  final JoinRole role;
  final JoinStatus status;
  final DateTime createdAt;
}

/// The answer to asking to join: linked straight away, or waiting.
sealed class JoinOutcome {
  const JoinOutcome();
}

class JoinLinked extends JoinOutcome {
  const JoinLinked(this.gymName);
  final String gymName;
}

class JoinPending extends JoinOutcome {
  const JoinPending(this.request);
  final JoinRequest request;
}

class GymJoinFailure implements Exception {
  const GymJoinFailure(this.message);
  final String message;
  @override
  String toString() => 'GymJoinFailure: $message';
}

class GymJoinRepository {
  GymJoinRepository(this._client);
  final Dio _client;

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const GymJoinFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw GymJoinFailure(switch (code) {
        'GYM_CODE_NOT_FOUND' => 'No gym has that code. Check it with your gym.',
        'ALREADY_IN_GYM' => 'You already belong to this gym.',
        'JOIN_REQUEST_PENDING' =>
          'You already asked to join this gym. Wait for the owner to answer.',
        'JOIN_REQUEST_NOT_FOUND' => 'This request is no longer waiting.',
        'PHONE_NOT_VERIFIED' =>
          'Verify your phone number in Sign-in & security first.',
        'PHONE_BELONGS_TO_ANOTHER_MEMBER' =>
          'Another member account already uses this phone in your gym.',
        'PHONE_BELONGS_TO_ANOTHER_TRAINER' =>
          'Another trainer account already uses this phone in your gym.',
        'JOIN_REQUEST_ACCOUNT_UNAVAILABLE' =>
          'This person no longer has an active account.',
        'MEMBER_PHONE_NOT_MOBILE' =>
          'This phone is not a 10-digit Indian mobile, so no code can be sent.',
        'INVALID_OTP' => 'That code is not correct or has expired.',
        'OTP_RESEND_TOO_SOON' => 'Wait a minute before sending another code.',
        'OTP_LIMIT_REACHED' =>
          'Too many codes for this number. Try again in an hour.',
        'OTP_DELIVERY_UNAVAILABLE' =>
          'The code could not be sent right now. Try again later.',
        'VALIDATION_ERROR' => 'Check the code and try again.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const GymJoinFailure('The server returned unexpected data.');
    }
  }

  // The person joining.
  Future<String> lookup(String code) => _call(
    () => _client.get<dynamic>(
      'join-requests/lookup',
      queryParameters: {'code': code.trim().toUpperCase()},
    ),
    (data) => (data as Map)['gymName'] as String,
  );

  Future<JoinOutcome> ask({
    required String code,
    required JoinRole role,
    required String name,
  }) => _call(
    () => _client.post<dynamic>(
      'join-requests',
      data: {
        'gymCode': code.trim().toUpperCase(),
        'role': role.wire,
        'name': name.trim(),
      },
    ),
    (data) => (data as Map)['status'] == 'linked'
        ? JoinLinked(data['gymName'] as String)
        : JoinPending(
            JoinRequest.fromJson(
              (data['request'] as Map).cast<String, dynamic>(),
            ),
          ),
  );

  Future<List<JoinRequest>> mine() => _call(
    () => _client.get<dynamic>('join-requests'),
    (data) => [
      for (final row in data as List)
        JoinRequest.fromJson((row as Map).cast<String, dynamic>()),
    ],
  );

  Future<void> cancel(String id) => _call(
    () => _client.post<dynamic>(
      'join-requests/$id/cancel',
      data: <String, Object>{},
    ),
    (_) {},
  );

  /// Links records a gym added for this verified phone since; returns how many.
  Future<int> checkAgain() => _call(
    () => _client.post<dynamic>(
      'account/link-profiles',
      data: <String, Object>{},
    ),
    (data) => ((data as Map)['linked'] as List).length,
  );

  // The owner.
  Future<({String code, String gymName})> joinCode(String gymId) => _call(
    () => _client.get<dynamic>('gyms/$gymId/join-code'),
    (data) => (
      code: (data as Map)['joinCode'] as String,
      gymName: data['gymName'] as String,
    ),
  );

  Future<List<JoinRequest>> pending(String gymId) => _call(
    () => _client.get<dynamic>('gyms/$gymId/join-requests'),
    (data) => [
      for (final row in data as List)
        JoinRequest.fromJson((row as Map).cast<String, dynamic>()),
    ],
  );

  Future<void> approve(String gymId, String id) => _call(
    () => _client.post<dynamic>(
      'gyms/$gymId/join-requests/$id/approve',
      data: <String, Object>{},
    ),
    (_) {},
  );

  Future<void> reject(String gymId, String id, {String? reason}) => _call(
    () => _client.post<dynamic>(
      'gyms/$gymId/join-requests/$id/reject',
      data: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    ),
    (_) {},
  );

  /// Texts the member a code; true when the phone is already verified.
  Future<bool> sendMemberPhoneCode(String gymId, String memberId) => _call(
    () => _client.post<dynamic>(
      'gyms/$gymId/members/$memberId/phone-verification',
      data: <String, Object>{},
    ),
    (data) => (data as Map)['phoneVerified'] == true,
  );

  Future<void> confirmMemberPhone(String gymId, String memberId, String code) =>
      _call(
        () => _client.post<dynamic>(
          'gyms/$gymId/members/$memberId/phone-verification/confirm',
          data: {'code': code.trim()},
        ),
        (_) {},
      );
}

final gymJoinRepositoryProvider = Provider<GymJoinRepository>(
  (ref) => GymJoinRepository(ref.watch(authenticatedApiClientProvider)),
);

final myJoinRequestsProvider = FutureProvider.autoDispose<List<JoinRequest>>(
  (ref) => ref.watch(gymJoinRepositoryProvider).mine(),
  retry: (_, _) => null,
);

final pendingJoinRequestsProvider =
    FutureProvider.autoDispose<List<JoinRequest>>((ref) async {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return const [];
      return ref.watch(gymJoinRepositoryProvider).pending(gym.gymId);
    }, retry: (_, _) => null);

final gymJoinCodeProvider =
    FutureProvider.autoDispose<({String code, String gymName})?>((ref) async {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(gymJoinRepositoryProvider).joinCode(gym.gymId);
    }, retry: (_, _) => null);
