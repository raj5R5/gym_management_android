import 'dart:async';

import 'package:gym_management_app/features/admin_dashboard/data/dashboard_repository.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';

import '../auth/auth_fakes.dart';

const gymA = '000000000000000000000001';
const gymB = '000000000000000000000002';
AuthIdentity adminIdentity({
  List<String> gyms = const [gymA],
  AuthRole role = AuthRole.admin,
  AccountStatus status = AccountStatus.active,
}) => AuthIdentity(
  user: syntheticIdentity().user,
  gymAccess: gyms
      .map(
        (id) => AuthGymAccess(
          id: 'grant-$id',
          gymId: id,
          role: role,
          status: status,
        ),
      )
      .toList(),
);
Map<String, dynamic> dashboardJson({
  bool empty = false,
  int revenue = 123456789,
}) => {
  'period': {
    'timezone': 'Asia/Kolkata',
    'from': '2026-03-01',
    'to': '2026-03-01',
    'startUtc': '2026-02-28T18:30:00.000Z',
    'endUtc': '2026-03-01T18:30:00.000Z',
    'branchId': null,
  },
  'members': {
    'total': empty ? 0 : 12,
    'active': empty ? 0 : 9,
    'inactive': empty ? 0 : 2,
    'suspended': empty ? 0 : 1,
  },
  'trainers': {
    'total': empty ? 0 : 3,
    'active': empty ? 0 : 2,
    'inactive': empty ? 0 : 1,
    'suspended': 0,
  },
  'subscriptions': {
    'currentlyActive': empty ? 0 : 8,
    'expiringSoon': empty ? 0 : 2,
    'expired': empty ? 0 : 4,
  },
  'payments': {
    'periodSuccessfulAmountPaise': empty ? 0 : revenue,
    'periodSuccessfulCount': empty ? 0 : 5,
  },
  'attendance': {
    'periodVisits': empty ? 0 : 20,
    'periodUniqueMembers': empty ? 0 : 10,
    'currentlyCheckedIn': empty ? 0 : 2,
  },
};

class FakeDashboardRepository implements DashboardRepository {
  Object? failure;
  Completer<GymDashboard>? gate;
  GymDashboard result = GymDashboard.fromJson(dashboardJson());
  final requests = <({String gymId, DashboardQuery query})>[];
  @override
  Future<GymDashboard> getDashboard(String gymId, DashboardQuery query) async {
    requests.add((gymId: gymId, query: query));
    if (gate != null) return gate!.future;
    if (failure != null) throw failure!;
    return result;
  }
}
