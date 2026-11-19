import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';
import 'visit_models.dart';

/// Membership state the server reported when it refused a check-in.
class MembershipNotActive implements Exception {
  const MembershipNotActive({
    required this.state,
    this.planName,
    this.endDate,
    this.frozenUntil,
  });
  final String state;
  final String? planName, endDate, frozenUntil;
  String get title =>
      state == 'frozen' ? 'Membership frozen' : 'Membership not active';

  static String _readable(String iso) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = DateTime.tryParse(iso);
    return day == null
        ? iso
        : '${day.day} ${months[day.month - 1]} ${day.year}';
  }

  String get message => switch (state) {
    'expired' =>
      '${planName == null ? 'The membership' : 'The $planName membership'} has expired. Renew it, or check in anyway.',
    'frozen' =>
      'This membership is frozen${frozenUntil == null ? '' : ' until ${_readable(frozenUntil!)}'}. Check in anyway?',
    'upcoming' =>
      '${planName == null ? 'The membership' : 'The $planName membership'} hasn’t started yet. Check in anyway?',
    _ => 'This member has no membership. Add a plan, or check in anyway.',
  };
}

class VisitFailure implements Exception {
  const VisitFailure(this.message);
  final String message;
  factory VisitFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return VisitFailure(switch (code) {
      'MEMBER_NOT_FOUND' => 'This member isn’t in this gym.',
      'MEMBER_NOT_ACTIVE' =>
        'This member profile is inactive or suspended. Reactivate it to check in.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'VisitFailure: $message';
}

class VisitRepository {
  VisitRepository(this._client);
  final Dio _client;
  static final _id = RegExp(r'^[a-fA-F0-9]{24}$');

  Future<Map<String, dynamic>> _data(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid visit envelope.');
      }
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      if (failure is Map && failure['code'] == 'MEMBERSHIP_NOT_ACTIVE') {
        final details = failure['details'] is Map
            ? failure['details'] as Map
            : const {};
        throw MembershipNotActive(
          state: details['membershipState'] as String? ?? 'none',
          planName: details['planName'] as String?,
          endDate: details['endDate'] as String?,
          frozenUntil: details['frozenUntil'] as String?,
        );
      }
      throw VisitFailure.fromDio(error);
    }
  }

  void _check(String value) {
    if (!_id.hasMatch(value)) {
      throw const VisitFailure('Invalid gym or member.');
    }
  }

  Future<CheckInResult> checkIn(
    String gymId,
    String memberId, {
    VisitMethod method = VisitMethod.manual,
    bool override = false,
  }) async {
    _check(gymId);
    _check(memberId);
    try {
      return CheckInResult.fromJson(
        await _data(
          () => _client.post<dynamic>(
            'gyms/$gymId/visits',
            data: {
              'memberId': memberId,
              'method': method.name,
              'override': override,
            },
          ),
        ),
      );
    } on FormatException {
      throw const VisitFailure('The server returned an unexpected check-in.');
    }
  }

  Future<TodayVisits> today(String gymId, {int page = 1}) async {
    _check(gymId);
    try {
      return TodayVisits.fromJson(
        await _data(
          () => _client.get<dynamic>(
            'gyms/$gymId/visits/today',
            queryParameters: {'page': '$page', 'limit': '50'},
          ),
        ),
      );
    } on FormatException {
      throw const VisitFailure('The server returned unexpected visits.');
    }
  }

  Future<MemberVisitHistory> history(
    String gymId,
    String memberId, {
    int page = 1,
  }) async {
    _check(gymId);
    _check(memberId);
    try {
      return MemberVisitHistory.fromJson(
        await _data(
          () => _client.get<dynamic>(
            'gyms/$gymId/members/$memberId/visits',
            queryParameters: {'page': '$page', 'limit': '10'},
          ),
        ),
      );
    } on FormatException {
      throw const VisitFailure('The server returned unexpected visits.');
    }
  }
}

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(ref.watch(authenticatedApiClientProvider)),
);

final todayVisitsProvider = FutureProvider.autoDispose<TodayVisits?>((ref) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(visitRepositoryProvider).today(gym.gymId);
}, retry: (_, _) => null);

final memberVisitHistoryProvider = FutureProvider.autoDispose
    .family<MemberVisitHistory?, String>((ref, memberId) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(visitRepositoryProvider).history(gym.gymId, memberId);
    }, retry: (_, _) => null);
