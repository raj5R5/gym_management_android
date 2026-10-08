import 'dart:async';
import 'package:gym_management_app/features/attendance/data/attendance_repository.dart';
import 'package:gym_management_app/features/attendance/data/attendance_failure.dart';
import 'package:gym_management_app/features/attendance/models/attendance_models.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';

const visitId = '000000000000000000000077';
const branchId = '000000000000000000000044';
Map<String, dynamic> visitJson({
  bool completed = false,
  bool display = false,
}) => {
  'id': visitId,
  'memberId': memberId,
  'branchId': branchId,
  'subscriptionId': subscriptionId,
  if (!display) 'gymId': gymA,
  if (display) 'memberName': 'Alex River',
  if (display) 'memberCode': 'ME01',
  if (display) 'branchName': 'Main',
  'status': completed ? 'completed' : 'open',
  'checkInAt': '2026-10-08T04:00:00.000Z',
  'checkOutAt': completed ? '2026-10-08T05:15:00.000Z' : null,
  'durationMs': completed ? 4500000 : null,
};
Map<String, dynamic> todayJson({bool empty = false, bool completed = true}) => {
  'date': '2026-10-08',
  'timezone': 'America/New_York',
  'summary': {
    'totalVisits': empty ? 0 : 1,
    'completedVisits': !empty && completed ? 1 : 0,
    'currentlyCheckedIn': !empty && !completed ? 1 : 0,
    'uniqueMembers': empty ? 0 : 1,
  },
  'visits': empty ? [] : [visitJson(completed: completed, display: true)],
};
Map<String, dynamic> attendanceEnvelope(
  Object data, {
  int page = 1,
  int total = 1,
}) => {
  'success': true,
  'data': data,
  'meta': {
    'requestId': 'synthetic-request',
    'pagination': {'page': page, 'limit': 20, 'total': total},
  },
};
Pagination pagination(int page, int total) =>
    Pagination.fromJson({'page': page, 'limit': 20, 'total': total});

class AttendanceMemberRepository extends FakeMemberRepository {
  bool noBranch = false;
  Completer<MemberProfile>? getGate;
  @override
  Future<MemberProfile> get(String gymId, String id) async {
    operations.add('get:$gymId:$id');
    if (failure != null) throw failure!;
    if (getGate != null) return getGate!.future;
    return MemberProfile.fromJson(
      profileJson(gymId: gymId)..['branchId'] = noBranch ? null : branchId,
    );
  }
}

class FakeAttendanceRepository implements AttendanceRepository {
  Object? failure;
  bool empty = false, opened = true, completed = true;
  int total = 1;
  Completer<AttendanceVisit>? writeGate;
  Completer<AttendanceToday>? todayGate;
  final calls = <String>[];
  final queries = <AttendanceQuery>[];
  int writes = 0;
  void _check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<AttendanceToday> today(String gymId, AttendanceQuery query) async {
    calls.add('today:$gymId:${query.page}');
    queries.add(query);
    _check();
    if (todayGate != null) return todayGate!.future;
    final isCompleted = query.status != VisitStatus.open;
    final none = empty || (isCompleted ? !completed : !opened);
    return AttendanceToday.fromResponse(
      todayJson(empty: none, completed: isCompleted),
      {
        'pagination': {'page': query.page, 'limit': 20, 'total': none ? 0 : 1},
      },
    );
  }

  @override
  Future<AttendancePage> openVisits(String gymId, int page) async {
    calls.add('open:$gymId:$page');
    _check();
    return AttendancePage(
      empty || !opened
          ? []
          : [AttendanceVisit.fromJson(visitJson()..['gymId'] = gymId)],
      pagination(page, empty || !opened ? 0 : total),
    );
  }

  @override
  Future<AttendanceVisit> checkIn(String gymId, MemberProfile member) async {
    if (member.branchId == null) {
      throw const AttendanceFailure('This member has no assigned branch.');
    }
    calls.add('check-in');
    writes++;
    _check();
    if (writeGate != null) return writeGate!.future;
    opened = true;
    empty = false;
    return AttendanceVisit.fromJson(visitJson()..['gymId'] = gymId);
  }

  @override
  Future<AttendanceVisit> checkOut(String gymId, String id) async {
    calls.add('check-out');
    writes++;
    _check();
    if (writeGate != null) return writeGate!.future;
    opened = false;
    completed = true;
    empty = false;
    return AttendanceVisit.fromJson(
      visitJson(completed: true)..['gymId'] = gymId,
    );
  }
}
