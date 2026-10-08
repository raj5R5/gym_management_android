import '../../../shared/models/profile_models.dart';
import '../../admin_dashboard/models/dashboard_models.dart' show CalendarDate;

enum VisitStatus { open, completed, cancelled }

class AttendanceVisit {
  AttendanceVisit.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      memberId = text(json, 'memberId'),
      gymId = optionalText(json, 'gymId'),
      branchId = text(json, 'branchId'),
      subscriptionId = text(json, 'subscriptionId'),
      memberName = optionalText(json, 'memberName'),
      memberCode = optionalText(json, 'memberCode'),
      branchName = optionalText(json, 'branchName'),
      status = VisitStatus.values.byName(text(json, 'status')),
      checkInAt = DateTime.parse(text(json, 'checkInAt')),
      checkOutAt = json['checkOutAt'] == null
          ? null
          : DateTime.parse(text(json, 'checkOutAt')),
      durationMs = json['durationMs'] == null
          ? null
          : integer(json, 'durationMs') {
    if (!checkInAt.isUtc ||
        checkOutAt != null &&
            (!checkOutAt!.isUtc || checkOutAt!.isBefore(checkInAt)) ||
        status == VisitStatus.open &&
            (checkOutAt != null || durationMs != null) ||
        status == VisitStatus.completed &&
            (checkOutAt == null || durationMs == null)) {
      throw const FormatException('Invalid attendance lifecycle.');
    }
  }
  final String id, memberId, branchId, subscriptionId;
  final String? gymId, memberName, memberCode, branchName;
  final VisitStatus status;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final int? durationMs;
}

class AttendancePage {
  AttendancePage(this.visits, this.pagination);
  final List<AttendanceVisit> visits;
  final Pagination pagination;
}

class AttendanceSummary {
  AttendanceSummary.fromJson(Map<String, dynamic> json)
    : total = integer(json, 'totalVisits'),
      completed = integer(json, 'completedVisits'),
      open = integer(json, 'currentlyCheckedIn'),
      uniqueMembers = integer(json, 'uniqueMembers');
  final int total, completed, open, uniqueMembers;
}

class AttendanceToday extends AttendancePage {
  AttendanceToday.fromResponse(
    Map<String, dynamic> data,
    Map<String, dynamic> meta,
  ) : date = CalendarDate.parse(text(data, 'date')),
      timezone = text(data, 'timezone'),
      summary = AttendanceSummary.fromJson(object(data['summary'])),
      super(
        items(data['visits'], AttendanceVisit.fromJson),
        Pagination.fromJson(object(meta['pagination'])),
      );
  final CalendarDate date;
  final String timezone;
  final AttendanceSummary summary;
}

class AttendanceQuery {
  AttendanceQuery({this.page = 1, this.status, this.memberId}) {
    if (page < 1 ||
        page > 10000 ||
        status == VisitStatus.cancelled ||
        memberId != null && !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(memberId!)) {
      throw const FormatException('Invalid attendance query.');
    }
  }
  final int page;
  final VisitStatus? status;
  final String? memberId;
  Map<String, dynamic> toParameters() => {
    'page': '$page',
    'limit': '20',
    if (status != null) 'status': status!.name,
    if (memberId != null) 'memberId': memberId,
  };
}

/// Formats the server duration; never subtracts client timestamps.
String formatVisitDuration(int milliseconds) {
  if (milliseconds < 0) throw ArgumentError.value(milliseconds);
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m ${seconds % 60}s';
}

String formatVisitTime(DateTime instant) {
  final local = instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)} ${local.timeZoneName}';
}
