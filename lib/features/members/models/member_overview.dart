import '../../admin_dashboard/models/dashboard_models.dart';
import 'member_models.dart';

/// Filters served by `GET gyms/:gymId/member-overview`.
enum MemberOverviewFilter {
  all,
  active,
  expiring,
  dues,
  expired,
  none,
  inactive,
}

extension MemberOverviewFilterLabel on MemberOverviewFilter {
  String get label => switch (this) {
    MemberOverviewFilter.all => 'All',
    MemberOverviewFilter.active => 'Active',
    MemberOverviewFilter.expiring => 'Expiring',
    MemberOverviewFilter.dues => 'Dues',
    MemberOverviewFilter.expired => 'Expired',
    MemberOverviewFilter.none => 'No plan',
    MemberOverviewFilter.inactive => 'Not visiting',
  };
}

enum OverviewMembershipState { active, upcoming, expired }

const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String _shortDay(DateTime day) => '${day.day} ${_shortMonths[day.month - 1]}';

int _count(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid member overview number.');
  }
  return value;
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid member overview text.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid member overview response.');
  }
  return value;
}

/// The membership shown for a member: current, else upcoming, else latest expired.
class OverviewMembership {
  OverviewMembership.fromJson(Map<String, dynamic> json)
    : state = OverviewMembershipState.values.byName(_text(json, 'state')),
      subscriptionId = _text(json, 'subscriptionId'),
      planName = _text(json, 'planName'),
      startDate = CalendarDate.parse(_text(json, 'startDate')),
      endDate = CalendarDate.parse(_text(json, 'endDate')),
      daysLeft = _count(json['daysLeft']),
      daysSinceExpiry = _count(json['daysSinceExpiry']),
      expiringSoon = json['expiringSoon'] == true,
      renewedAhead = json['renewedAhead'] == true,
      frozenUntil = json['frozenUntil'] is String
          ? CalendarDate.parse(json['frozenUntil'] as String)
          : null;
  final OverviewMembershipState state;
  final String subscriptionId, planName;
  final CalendarDate startDate;

  /// Exclusive end date (the first day without access).
  final CalendarDate endDate;
  final int daysLeft, daysSinceExpiry;
  final bool expiringSoon, renewedAhead;

  /// Day the member is back from a freeze that covers today, if any.
  final CalendarDate? frozenUntil;
  bool get frozen => frozenUntil != null;

  int get totalDays => endDate.value.difference(startDate.value).inDays;

  /// Share of the period already used, 0..1, for the progress bar.
  double get usedFraction => totalDays <= 0
      ? 1
      : ((totalDays - daysLeft) / totalDays).clamp(0, 1).toDouble();

  /// Plain-language status, e.g. "3 days left" or "Expired 10 days ago".
  String get statusLabel => frozen
      ? 'Frozen until ${_shortDay(frozenUntil!.value)}'
      : switch (state) {
          OverviewMembershipState.active =>
            daysLeft == 1 ? 'Last day today' : '$daysLeft days left',
          OverviewMembershipState.upcoming => 'Starts soon',
          OverviewMembershipState.expired =>
            daysSinceExpiry == 0
                ? 'Expired today'
                : daysSinceExpiry == 1
                ? 'Expired yesterday'
                : 'Expired $daysSinceExpiry days ago',
        };
}

class MemberOverviewRow {
  MemberOverviewRow.fromJson(Map<String, dynamic> json)
    : member = MemberProfile.fromJson(_object(json['member'])),
      membership = json['membership'] == null
          ? null
          : OverviewMembership.fromJson(_object(json['membership'])),
      balancePaise = _count(json['balancePaise']),
      dueSubscriptionId = json['dueSubscriptionId'] as String?,
      lastVisitDate = json['lastVisitDate'] as String?,
      daysSinceLastVisit = json['daysSinceLastVisit'] is int
          ? json['daysSinceLastVisit'] as int
          : null {
    if (balancePaise > 0 && (dueSubscriptionId?.isEmpty ?? true)) {
      throw const FormatException('Missing due membership.');
    }
  }
  final MemberProfile member;
  final OverviewMembership? membership;
  final int balancePaise;
  final String? dueSubscriptionId;

  /// Last check-in day, or null when the member has never checked in.
  final String? lastVisitDate;
  final int? daysSinceLastVisit;

  String get lastVisitLabel => switch (daysSinceLastVisit) {
    null => 'No visits yet',
    0 => 'Visited today',
    1 => 'Last visit yesterday',
    final days => 'Last visit $days days ago',
  };
}

class MemberOverviewCounts {
  MemberOverviewCounts.fromJson(Map<String, dynamic> json)
    : values = {
        for (final filter in MemberOverviewFilter.values)
          // Servers without visit tracking omit `inactive`.
          filter:
              filter == MemberOverviewFilter.inactive &&
                  json[filter.name] == null
              ? 0
              : _count(json[filter.name]),
      };
  final Map<MemberOverviewFilter, int> values;
  int operator [](MemberOverviewFilter filter) => values[filter] ?? 0;
}

class MemberOverviewPage {
  MemberOverviewPage.fromJson(Map<String, dynamic> json)
    : counts = MemberOverviewCounts.fromJson(_object(json['counts'])),
      duesTotalPaise = _count(json['duesTotalPaise']),
      timezone = _text(_object(json['calendar']), 'timezone'),
      rows = List.unmodifiable(
        (json['data'] is List
                ? json['data'] as List
                : throw const FormatException('Invalid rows.'))
            .map((row) => MemberOverviewRow.fromJson(_object(row))),
      ),
      pagination = Pagination.fromJson(_object(json['pagination']));
  final MemberOverviewCounts counts;
  final int duesTotalPaise;
  final String timezone;
  final List<MemberOverviewRow> rows;
  final Pagination pagination;
}

class MemberOverviewQuery {
  const MemberOverviewQuery({
    this.filter = MemberOverviewFilter.all,
    this.search = '',
    this.page = 1,
    this.limit = 20,
  });
  final MemberOverviewFilter filter;
  final String search;
  final int page, limit;

  Map<String, String> toParameters() => {
    'filter': filter.name,
    'page': '$page',
    'limit': '$limit',
    if (search.trim().isNotEmpty) 'search': search.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is MemberOverviewQuery &&
      other.filter == filter &&
      other.search == search &&
      other.page == page &&
      other.limit == limit;
  @override
  int get hashCode => Object.hash(filter, search, page, limit);
}
