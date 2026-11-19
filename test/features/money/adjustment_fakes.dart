import 'package:gym_management_app/features/adjustments/adjustments.dart';

Map<String, dynamic> adjustmentsJson({
  String subscriptionId = 'subscription-1',
  int durationDays = 90,
  int frozenDays = 0,
  int listPricePaise = 400000,
  int discountPaise = 0,
  int paidPaise = 0,
  String? blocker,
  List<Map<String, dynamic>> freezes = const [],
}) => {
  'subscriptionId': subscriptionId,
  'today': '2026-11-14',
  'startDate': '2026-11-01',
  'endDate': '2027-01-30',
  'durationDays': durationDays,
  'frozenDays': frozenDays,
  'listPricePaise': listPricePaise,
  'discountPaise': discountPaise,
  'pricePaise': listPricePaise - discountPaise,
  'paidPaise': paidPaise,
  'balancePaise': listPricePaise - discountPaise - paidPaise,
  'freeze': {
    'allowed': blocker == null,
    'blocker': blocker,
    'daysLeft': 30 - frozenDays,
    'maxTotalDays': 30,
    'minPlanDays': 90,
    'earliestStart': '2026-11-14',
    'latestStart': '2027-01-29',
  },
  'freezes': freezes,
  'discounts': <Map<String, dynamic>>[],
};

/// Records freeze/discount calls; returns [current] adjusted by them.
class FakeAdjustmentRepository implements AdjustmentRepository {
  FakeAdjustmentRepository({Map<String, dynamic>? json})
    : current = json ?? adjustmentsJson();
  Map<String, dynamic> current;
  final calls = <String>[];

  @override
  Future<MembershipAdjustments> get(
    String gymId,
    String subscriptionId,
  ) async => MembershipAdjustments.fromJson(current);

  @override
  Future<MembershipAdjustments> freeze(
    String gymId,
    String subscriptionId, {
    required DateTime start,
    required int days,
    String? reason,
  }) async {
    calls.add('freeze:${isoDay(start)}:$days');
    current = adjustmentsJson(
      frozenDays: (current['frozenDays'] as int) + days,
      freezes: [
        {
          'id': 'f1',
          'startDate': isoDay(start),
          'endDate': isoDay(start.add(Duration(days: days))),
          'days': days,
          'status': 'current',
          'reason': reason,
        },
      ],
    );
    return MembershipAdjustments.fromJson(current);
  }

  @override
  Future<MembershipAdjustments> endFreeze(
    String gymId,
    String subscriptionId,
    String freezeId,
  ) async {
    calls.add('end:$freezeId');
    return MembershipAdjustments.fromJson(current);
  }

  @override
  Future<MembershipAdjustments> discount(
    String gymId,
    String subscriptionId, {
    int? amountPaise,
    double? percent,
    String? reason,
  }) async {
    calls.add('discount:${amountPaise ?? '$percent%'}');
    return MembershipAdjustments.fromJson(current);
  }
}
