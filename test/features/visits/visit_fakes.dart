import 'package:gym_management_app/features/visits/visit_models.dart';
import 'package:gym_management_app/features/visits/visit_repository.dart';

/// Records check-ins; members in [expired] are refused unless overridden.
class FakeVisitRepository implements VisitRepository {
  final calls = <({String memberId, VisitMethod method, bool override})>[];
  final expired = <String>{};

  Map<String, dynamic> _visit(String memberId, bool override) => {
    'id': 'visit-${calls.length}',
    'memberId': memberId,
    'visitDate': '2026-11-14',
    'checkedInAt': '2026-11-14T08:40:00.000Z',
    'method': calls.last.method.name,
    'membershipState': override ? 'expired' : 'active',
    'override': override,
  };

  @override
  Future<CheckInResult> checkIn(
    String gymId,
    String memberId, {
    VisitMethod method = VisitMethod.manual,
    bool override = false,
  }) async {
    calls.add((memberId: memberId, method: method, override: override));
    if (expired.contains(memberId) && !override) {
      throw const MembershipNotActive(state: 'expired', planName: 'Monthly');
    }
    return CheckInResult.fromJson({
      'member': {
        'id': memberId,
        'memberCode': 'ME01',
        'firstName': 'Alex',
        'lastName': 'River',
        'phone': '+91 9876543210',
        'status': 'active',
      },
      'membership': null,
      'balancePaise': 0,
      'visit': _visit(memberId, override),
      'alreadyCheckedIn': false,
    });
  }

  @override
  Future<TodayVisits> today(String gymId, {int page = 1}) async =>
      TodayVisits.fromJson({
        'date': '2026-11-14',
        'total': calls
            .where((call) => !expired.contains(call.memberId) || call.override)
            .length,
        'overrides': calls.where((call) => call.override).length,
        'data': <Map<String, dynamic>>[],
        'pagination': {'page': page, 'limit': 50, 'total': 0},
      });

  @override
  Future<MemberVisitHistory> history(
    String gymId,
    String memberId, {
    int page = 1,
  }) async => MemberVisitHistory.fromJson({
    'visitsLast30Days': 0,
    'lastVisitDate': null,
    'daysSinceLastVisit': null,
    'data': <Map<String, dynamic>>[],
    'pagination': {'page': page, 'limit': 10, 'total': 0},
  });
}
