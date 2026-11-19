import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

enum BranchPeriod { today, last7Days, thisMonth }

extension BranchPeriodText on BranchPeriod {
  String get label => switch (this) {
    BranchPeriod.today => 'Today',
    BranchPeriod.last7Days => '7 days',
    BranchPeriod.thisMonth => 'This month',
  };
}

class BranchRow {
  BranchRow.fromJson(Map<String, dynamic> json)
    : gymId = json['gymId'] as String,
      name = json['name'] as String,
      activeMembers = json['activeMembers'] as int,
      totalMembers = json['totalMembers'] as int,
      collectedPaise = json['collectedPaise'] as int,
      duesPaise = json['duesPaise'] as int,
      expiringSoon = json['expiringSoon'] as int? ?? 0,
      checkInsToday = json['checkInsToday'] as int? ?? 0,
      expensesPaise = json['expensesPaise'] as int? ?? 0;
  final String gymId, name;
  final int activeMembers, totalMembers, collectedPaise, duesPaise;
  final int expiringSoon, checkInsToday, expensesPaise;
}

/// Every branch (gym) the owner administers, with totals.
class BranchSummary {
  BranchSummary.fromJson(Map<String, dynamic> json)
    : branches = List.unmodifiable(
        (json['branches'] as List).map(
          (row) => BranchRow.fromJson(row as Map<String, dynamic>),
        ),
      ),
      totals = BranchRow.fromJson({
        'gymId': 'all',
        'name': 'All branches',
        ...(json['totals'] as Map<String, dynamic>),
      });
  final List<BranchRow> branches;
  final BranchRow totals;
}

class BranchFailure implements Exception {
  const BranchFailure(this.message);
  final String message;
  factory BranchFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return BranchFailure(switch (code) {
      'DUPLICATE_GYM_NAME' =>
        'A gym with this name already exists. Add the area, e.g. “Iron Gym – Andheri”.',
      'BRANCH_LIMIT_REACHED' =>
        'You have reached the maximum number of branches.',
      'VALIDATION_ERROR' => 'Enter a branch name of 2–120 characters.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
}

class BranchRepository {
  BranchRepository(this._client);
  final Dio _client;

  Future<BranchSummary> summary(BranchPeriod period) async {
    try {
      final body = (await _client.get<dynamic>(
        'branches/summary',
        queryParameters: {'preset': period.name},
      )).data;
      if (body is! Map || body['success'] != true) {
        throw const BranchFailure('Unexpected response.');
      }
      return BranchSummary.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw BranchFailure.fromDio(error);
    } on TypeError {
      throw const BranchFailure('The server returned an unexpected summary.');
    }
  }

  /// Returns the new branch's gym id.
  Future<String> create({
    required String name,
    String? fromGymId,
    required bool copyPlans,
    required bool copySettings,
  }) async {
    try {
      final body = (await _client.post<dynamic>(
        'branches',
        data: {
          'name': name,
          'fromGymId': ?fromGymId,
          'copyPlans': fromGymId != null && copyPlans,
          'copySettings': fromGymId != null && copySettings,
        },
      )).data;
      if (body is! Map || body['success'] != true) {
        throw const BranchFailure('Unexpected response.');
      }
      return (body['data'] as Map)['gymId'] as String;
    } on DioException catch (error) {
      throw BranchFailure.fromDio(error);
    }
  }
}

final branchRepositoryProvider = Provider<BranchRepository>(
  (ref) => BranchRepository(ref.watch(authenticatedApiClientProvider)),
);

final branchSummaryProvider = FutureProvider.autoDispose
    .family<BranchSummary?, BranchPeriod>((ref, period) {
      // Re-read when the account's gyms change (e.g. after adding a branch).
      final gyms = ref.watch(adminGymIdsProvider);
      if (gyms.isEmpty) return null;
      return ref.watch(branchRepositoryProvider).summary(period);
    }, retry: (_, _) => null);

/// gymId → branch name, for the gym switcher. Empty until loaded.
final branchNamesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final gyms = ref.watch(adminGymIdsProvider);
  if (gyms.length < 2) return const {};
  final summary = ref
      .watch(branchSummaryProvider(BranchPeriod.today))
      .asData
      ?.value;
  return {
    for (final row in summary?.branches ?? const <BranchRow>[])
      row.gymId: row.name,
  };
});
