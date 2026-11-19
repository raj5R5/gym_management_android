import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

class MembershipFreeze {
  MembershipFreeze.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      startDate = DateTime.parse(json['startDate'] as String),
      endDate = DateTime.parse(json['endDate'] as String),
      days = json['days'] as int,
      status = json['status'] as String,
      reason = json['reason'] as String?;
  final String id, status;

  /// [startDate, endDate): endDate is the day the member is back.
  final DateTime startDate, endDate;
  final int days;
  final String? reason;
  bool get canEndEarly => status == 'current' || status == 'upcoming';
}

class MembershipDiscount {
  MembershipDiscount.fromJson(Map<String, dynamic> json)
    : amountPaise = json['amountPaise'] as int,
      percent = (json['percent'] as num?)?.toDouble(),
      reason = json['reason'] as String?;
  final int amountPaise;
  final double? percent;
  final String? reason;
}

/// Freeze/discount state of one membership, with the rules applied.
class MembershipAdjustments {
  MembershipAdjustments.fromJson(Map<String, dynamic> json)
    : subscriptionId = json['subscriptionId'] as String,
      today = DateTime.parse(json['today'] as String),
      endDate = DateTime.parse(json['endDate'] as String),
      durationDays = json['durationDays'] as int,
      frozenDays = json['frozenDays'] as int,
      listPricePaise = json['listPricePaise'] as int,
      discountPaise = json['discountPaise'] as int,
      pricePaise = json['pricePaise'] as int,
      paidPaise = json['paidPaise'] as int,
      balancePaise = json['balancePaise'] as int,
      freezeAllowed = (json['freeze'] as Map)['allowed'] == true,
      freezeBlocker = (json['freeze'] as Map)['blocker'] as String?,
      freezeDaysLeft = (json['freeze'] as Map)['daysLeft'] as int,
      maxFreezeDays = (json['freeze'] as Map)['maxTotalDays'] as int,
      minPlanDays = (json['freeze'] as Map)['minPlanDays'] as int,
      earliestStart = DateTime.parse(
        (json['freeze'] as Map)['earliestStart'] as String,
      ),
      latestStart = DateTime.parse(
        (json['freeze'] as Map)['latestStart'] as String,
      ),
      freezes = List.unmodifiable(
        (json['freezes'] as List).map(
          (row) => MembershipFreeze.fromJson(row as Map<String, dynamic>),
        ),
      ),
      discounts = List.unmodifiable(
        (json['discounts'] as List).map(
          (row) => MembershipDiscount.fromJson(row as Map<String, dynamic>),
        ),
      );
  final String subscriptionId;
  final DateTime today, endDate, earliestStart, latestStart;
  final int durationDays, frozenDays, listPricePaise, discountPaise;
  final int pricePaise, paidPaise, balancePaise;
  final bool freezeAllowed;
  final String? freezeBlocker;
  final int freezeDaysLeft, maxFreezeDays, minPlanDays;
  final List<MembershipFreeze> freezes;
  final List<MembershipDiscount> discounts;

  /// Plain reason a freeze isn't possible, for the owner.
  String? get freezeBlockedReason => switch (freezeBlocker) {
    null => null,
    'plan_too_short' =>
      'Only plans of $minPlanDays days or more can be frozen.',
    'no_days_left' => 'All $maxFreezeDays freeze days have been used.',
    'renewal_queued' =>
      'A renewal already starts after this membership, so it can’t be pushed back.',
    'ended' => 'This membership has ended.',
    'cancelled' => 'This membership was cancelled.',
    _ => 'This membership can’t be frozen.',
  };
}

class AdjustmentFailure implements Exception {
  const AdjustmentFailure(this.message);
  final String message;
  factory AdjustmentFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final failure = data is Map ? data['error'] : null;
    final code = failure is Map ? failure['code'] : null;
    final details = failure is Map && failure['details'] is Map
        ? failure['details'] as Map
        : const {};
    return AdjustmentFailure(switch (code) {
      'FREEZE_NOT_ALLOWED' => switch (details['blocker']) {
        'too_many_days' =>
          'Only ${details['daysLeft']} freeze days are left on this membership.',
        'start_out_of_range' =>
          'A freeze must start today or later, before the membership ends.',
        'later_freeze' => 'End the later freeze first, then this one.',
        'freeze_finished' => 'This freeze has already finished.',
        _ => 'This membership can’t be frozen.',
      },
      'FREEZE_OVERLAP' => 'These dates overlap another freeze.',
      'DISCOUNT_EXCEEDS_BALANCE' =>
        'A discount can’t be more than the unpaid amount.',
      'SUBSCRIPTION_CANCELLED' => 'This membership was cancelled.',
      'ADJUSTMENT_CONFLICT' =>
        'This membership just changed. Reload and try again.',
      'VALIDATION_ERROR' => 'Check the values and try again.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'AdjustmentFailure: $message';
}

String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class AdjustmentRepository {
  AdjustmentRepository(this._client);
  final Dio _client;

  String _path(String gymId, String subscriptionId) {
    final id = RegExp(r'^[a-fA-F0-9]{24}$');
    if (!id.hasMatch(gymId) || !id.hasMatch(subscriptionId)) {
      throw const AdjustmentFailure('Invalid membership.');
    }
    return 'gyms/$gymId/subscriptions/$subscriptionId/adjustments';
  }

  Future<MembershipAdjustments> _send(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const AdjustmentFailure('Unexpected response.');
      }
      return MembershipAdjustments.fromJson(
        body['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw AdjustmentFailure.fromDio(error);
    } on TypeError {
      throw const AdjustmentFailure('The server returned unexpected details.');
    }
  }

  Future<MembershipAdjustments> get(String gymId, String subscriptionId) =>
      _send(() => _client.get<dynamic>(_path(gymId, subscriptionId)));

  Future<MembershipAdjustments> freeze(
    String gymId,
    String subscriptionId, {
    required DateTime start,
    required int days,
    String? reason,
  }) => _send(
    () => _client.post<dynamic>(
      '${_path(gymId, subscriptionId)}/freezes',
      data: {'startDate': isoDay(start), 'days': days, 'reason': ?reason},
    ),
  );

  Future<MembershipAdjustments> endFreeze(
    String gymId,
    String subscriptionId,
    String freezeId,
  ) => _send(
    () => _client.post<dynamic>(
      '${_path(gymId, subscriptionId)}/freezes/$freezeId/end',
    ),
  );

  /// Exactly one of [amountPaise] or [percent].
  Future<MembershipAdjustments> discount(
    String gymId,
    String subscriptionId, {
    int? amountPaise,
    double? percent,
    String? reason,
  }) => _send(
    () => _client.post<dynamic>(
      '${_path(gymId, subscriptionId)}/discounts',
      data: {
        'amountPaise': ?amountPaise,
        'percent': ?percent,
        'reason': ?reason,
      },
    ),
  );
}

final adjustmentRepositoryProvider = Provider<AdjustmentRepository>(
  (ref) => AdjustmentRepository(ref.watch(authenticatedApiClientProvider)),
);

final membershipAdjustmentsProvider = FutureProvider.autoDispose
    .family<MembershipAdjustments?, String>((ref, subscriptionId) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref
          .watch(adjustmentRepositoryProvider)
          .get(gym.gymId, subscriptionId);
    }, retry: (_, _) => null);
