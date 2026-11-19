import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/providers/auth_providers.dart';
import 'models/member_models.dart';

/// An active member's next birthday, counted in gym-local days.
class UpcomingBirthday {
  UpcomingBirthday.fromJson(Map<String, dynamic> json)
    : member = MemberProfile.fromJson(json['member'] as Map<String, dynamic>),
      daysUntil = json['daysUntil'] as int,
      turning = json['turning'] as int;
  final MemberProfile member;
  final int daysUntil, turning;
  String get whenLabel => switch (daysUntil) {
    0 => 'Today · turns $turning',
    1 => 'Tomorrow · turns $turning',
    _ => 'In $daysUntil days · turns $turning',
  };
}

final upcomingBirthdaysProvider =
    FutureProvider.autoDispose<List<UpcomingBirthday>?>((ref) async {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      final Dio client = ref.watch(authenticatedApiClientProvider);
      final body = (await client.get<dynamic>(
        'gyms/${gym.gymId}/member-overview/birthdays',
        queryParameters: {'days': '7'},
      )).data;
      if (body is! Map || body['success'] != true) {
        throw const FormatException('Invalid birthdays response.');
      }
      return List.unmodifiable(
        ((body['data'] as Map)['data'] as List).map(
          (row) => UpcomingBirthday.fromJson(row as Map<String, dynamic>),
        ),
      );
    }, retry: (_, _) => null);
