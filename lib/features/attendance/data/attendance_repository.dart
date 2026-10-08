import 'package:dio/dio.dart';
import '../../members/models/member_models.dart';
import '../models/attendance_models.dart';
import 'attendance_failure.dart';

abstract interface class AttendanceRepository {
  Future<AttendanceToday> today(String gymId, AttendanceQuery query);
  Future<AttendancePage> openVisits(String gymId, int page);
  Future<AttendanceVisit> checkIn(String gymId, MemberProfile member);
  Future<AttendanceVisit> checkOut(String gymId, String visitId);
}

class DioAttendanceRepository implements AttendanceRepository {
  DioAttendanceRepository(this._client);
  final Dio _client;
  void _id(String id) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
      throw const AttendanceFailure('Invalid attendance context.');
    }
  }

  String _path(String gymId) {
    _id(gymId);
    return 'gyms/$gymId/attendance';
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() send,
    T Function(Map<String, dynamic>) parse, {
    bool writing = false,
  }) async {
    try {
      final response = object((await send()).data);
      if (response['success'] != true) {
        throw const FormatException('Invalid envelope.');
      }
      return parse(response);
    } on DioException catch (error) {
      throw AttendanceFailure.fromDio(error, writing: writing);
    } on AttendanceFailure {
      rethrow;
    } catch (_) {
      throw AttendanceFailure(
        writing
            ? 'The server result could not be verified. Recheck attendance before another attempt.'
            : 'The server returned unexpected attendance information.',
        uncertain: writing,
        recheck: writing,
      );
    }
  }

  void _page(Pagination pagination, int page, int count) {
    if (pagination.page != page || pagination.limit != 20 || count > 20) {
      throw const FormatException('Pagination mismatch.');
    }
  }

  AttendanceVisit _visit(
    Map<String, dynamic> json,
    String gymId, {
    VisitStatus? status,
  }) {
    final visit = AttendanceVisit.fromJson(json);
    for (final id in [
      visit.id,
      visit.memberId,
      visit.branchId,
      visit.subscriptionId,
    ]) {
      _id(id);
    }
    if (visit.gymId != gymId || status != null && visit.status != status) {
      throw const FormatException('Visit scope mismatch.');
    }
    return visit;
  }

  @override
  Future<AttendanceToday> today(String gymId, AttendanceQuery query) {
    final path = '${_path(gymId)}/today';
    return _request(
      () => _client.get(path, queryParameters: query.toParameters()),
      (response) {
        final result = AttendanceToday.fromResponse(
          object(response['data']),
          object(response['meta']),
        );
        _page(result.pagination, query.page, result.visits.length);
        if (result.pagination.total != result.summary.total) {
          throw const FormatException('Count mismatch.');
        }
        for (final visit in result.visits) {
          for (final id in [
            visit.id,
            visit.memberId,
            visit.branchId,
            visit.subscriptionId,
          ]) {
            _id(id);
          }
          if (visit.memberName == null ||
              visit.memberCode == null ||
              visit.branchName == null ||
              visit.status == VisitStatus.cancelled ||
              query.status != null && visit.status != query.status ||
              query.memberId != null && visit.memberId != query.memberId) {
            throw const FormatException('Visit filter mismatch.');
          }
        }
        return result;
      },
    );
  }

  @override
  Future<AttendancePage> openVisits(String gymId, int page) {
    final path = _path(gymId);
    final query = AttendanceQuery(page: page, status: VisitStatus.open);
    return _request(
      () => _client.get(path, queryParameters: query.toParameters()),
      (response) {
        final visits = items(
          response['data'],
          (json) => _visit(json, gymId, status: VisitStatus.open),
        );
        final pagination = Pagination.fromJson(
          object(object(response['meta'])['pagination']),
        );
        _page(pagination, page, visits.length);
        return AttendancePage(visits, pagination);
      },
    );
  }

  @override
  Future<AttendanceVisit> checkIn(String gymId, MemberProfile member) async {
    final memberId = member.id;
    final path = '${_path(gymId)}/check-in';
    _id(memberId);
    // The controller supplies a freshly read, scoped profile, never branch input.
    if (member.gymId != gymId) {
      throw const AttendanceFailure(
        'Member scope changed. Refresh the member.',
      );
    }
    final branchId = member.branchId;
    if (branchId == null) {
      throw const AttendanceFailure(
        'This member has no assigned branch. Attendance requires an active assigned branch; branch management is not available in this app yet.',
      );
    }
    _id(branchId);
    return _request(
      () => _client.post(
        path,
        data: {'memberId': memberId, 'branchId': branchId},
      ),
      (response) {
        final visit = _visit(
          object(response['data']),
          gymId,
          status: VisitStatus.open,
        );
        if (visit.memberId != memberId || visit.branchId != branchId) {
          throw const FormatException('Check-in mismatch.');
        }
        return visit;
      },
      writing: true,
    );
  }

  @override
  Future<AttendanceVisit> checkOut(String gymId, String visitId) {
    final path = '${_path(gymId)}/$visitId/check-out';
    _id(visitId);
    return _request(() => _client.post(path, data: <String, dynamic>{}), (
      response,
    ) {
      final visit = _visit(
        object(response['data']),
        gymId,
        status: VisitStatus.completed,
      );
      if (visit.id != visitId) {
        throw const FormatException('Check-out mismatch.');
      }
      return visit;
    }, writing: true);
  }
}
