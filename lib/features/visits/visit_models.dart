import '../members/models/member_models.dart';
import '../members/models/member_overview.dart';

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid visit response.');
  }
  return value;
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid visit text.');
  }
  return value;
}

int _count(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid visit number.');
  }
  return value;
}

enum VisitMethod { manual, qr }

class Visit {
  Visit.fromJson(Map<String, dynamic> json)
    : id = _text(json, 'id'),
      memberId = _text(json, 'memberId'),
      visitDate = _text(json, 'visitDate'),
      checkedInAt = DateTime.parse(_text(json, 'checkedInAt')).toLocal(),
      method = VisitMethod.values.byName(_text(json, 'method')),
      membershipState = _text(json, 'membershipState'),
      override = json['override'] == true;
  final String id, memberId, visitDate, membershipState;
  final DateTime checkedInAt;
  final VisitMethod method;

  /// Entered without an active membership, approved at the desk.
  final bool override;
}

/// Result of a check-in: who came in, their membership and whether it was a repeat.
class CheckInResult {
  CheckInResult.fromJson(Map<String, dynamic> json)
    : member = MemberProfile.fromJson(_object(json['member'])),
      membership = json['membership'] == null
          ? null
          : OverviewMembership.fromJson(_object(json['membership'])),
      balancePaise = _count(json['balancePaise']),
      visit = Visit.fromJson(_object(json['visit'])),
      alreadyCheckedIn = json['alreadyCheckedIn'] == true;
  final MemberProfile member;
  final OverviewMembership? membership;
  final int balancePaise;
  final Visit visit;
  final bool alreadyCheckedIn;
}

class TodayVisit {
  TodayVisit.fromJson(Map<String, dynamic> json)
    : visit = Visit.fromJson(_object(json['visit'])),
      member = MemberProfile.fromJson(_object(json['member']));
  final Visit visit;
  final MemberProfile member;
}

class TodayVisits {
  TodayVisits.fromJson(Map<String, dynamic> json)
    : date = _text(json, 'date'),
      total = _count(json['total']),
      overrides = _count(json['overrides']),
      rows = List.unmodifiable(
        (json['data'] as List).map((row) => TodayVisit.fromJson(_object(row))),
      ),
      pagination = Pagination.fromJson(_object(json['pagination']));
  final String date;
  final int total, overrides;
  final List<TodayVisit> rows;
  final Pagination pagination;
}

class MemberVisitHistory {
  MemberVisitHistory.fromJson(Map<String, dynamic> json)
    : visitsLast30Days = _count(json['visitsLast30Days']),
      lastVisitDate = json['lastVisitDate'] as String?,
      daysSinceLastVisit = json['daysSinceLastVisit'] as int?,
      visits = List.unmodifiable(
        (json['data'] as List).map((row) => Visit.fromJson(_object(row))),
      ),
      pagination = Pagination.fromJson(_object(json['pagination']));
  final int visitsLast30Days;
  final String? lastVisitDate;
  final int? daysSinceLastVisit;
  final List<Visit> visits;
  final Pagination pagination;

  String get lastVisitLabel => switch (daysSinceLastVisit) {
    null => 'No visits yet',
    0 => 'Today',
    1 => 'Yesterday',
    final days => '$days days ago',
  };
}

/// A member's check-in QR. Scoped to one gym so another gym's card is rejected.
abstract final class MemberQrCode {
  static const _prefix = 'MDK1';
  static String encode({required String gymId, required String memberId}) =>
      '$_prefix:$gymId:$memberId';

  /// Returns the member id when [raw] is a MuscleDesk card for [gymId].
  static String? memberIdFor(String raw, {required String gymId}) {
    final parts = raw.trim().split(':');
    final id = RegExp(r'^[a-fA-F0-9]{24}$');
    if (parts.length != 3 ||
        parts[0] != _prefix ||
        parts[1] != gymId ||
        !id.hasMatch(parts[2])) {
      return null;
    }
    return parts[2];
  }

  static bool isOtherGym(String raw, {required String gymId}) {
    final parts = raw.trim().split(':');
    return parts.length == 3 && parts[0] == _prefix && parts[1] != gymId;
  }
}
