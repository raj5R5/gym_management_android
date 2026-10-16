/// A calendar date, independent of the phone's timezone and DST offsets.
class CalendarDate implements Comparable<CalendarDate> {
  CalendarDate(int year, int month, int day)
    : value = DateTime.utc(year, month, day) {
    if (year < 1 ||
        year > 9999 ||
        value.year != year ||
        value.month != month ||
        value.day != day) {
      throw const FormatException('Invalid calendar date.');
    }
  }
  factory CalendarDate.parse(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('Invalid calendar date.');
    }
    final parts = text.split('-').map(int.parse).toList();
    return CalendarDate(parts[0], parts[1], parts[2]);
  }
  factory CalendarDate.fromPicker(DateTime date) =>
      CalendarDate(date.year, date.month, date.day);
  final DateTime value;
  @override
  String toString() =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  @override
  int compareTo(CalendarDate other) => value.compareTo(other.value);
}

/// All-branch query for M27. No date means the backend's gym-local today.
/// Future filters belong here; widgets never construct endpoint parameters.
enum DashboardDateFilter { today, last7Days, thisMonth, customRange }

class DashboardQuery {
  const DashboardQuery.today()
    : filter = DashboardDateFilter.today,
      from = null,
      to = null;
  const DashboardQuery.last7Days()
    : filter = DashboardDateFilter.last7Days,
      from = null,
      to = null;
  const DashboardQuery.thisMonth()
    : filter = DashboardDateFilter.thisMonth,
      from = null,
      to = null;
  DashboardQuery.range(this.from, this.to)
    : filter = DashboardDateFilter.customRange {
    if (from == null ||
        to == null ||
        from!.compareTo(to!) > 0 ||
        to!.value.difference(from!.value).inDays >= 366 ||
        to.toString() == '9999-12-31') {
      throw const FormatException(
        'Choose an inclusive range of 1 to 366 days.',
      );
    }
  }
  final CalendarDate? from;
  final CalendarDate? to;
  final DashboardDateFilter filter;
  Map<String, String> toParameters() => switch (filter) {
    DashboardDateFilter.today => {},
    DashboardDateFilter.last7Days => {'preset': 'last7Days'},
    DashboardDateFilter.thisMonth => {'preset': 'thisMonth'},
    DashboardDateFilter.customRange => {
      'from': from.toString(),
      'to': to.toString(),
    },
  };
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid dashboard response.');
  }
  return value;
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid dashboard response.');
  }
  return value;
}

int _count(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid dashboard number.');
  }
  return value;
}

class DashboardPeriod {
  DashboardPeriod.fromJson(Map<String, dynamic> json)
    : timezone = _text(json, 'timezone'),
      from = CalendarDate.parse(_text(json, 'from')),
      to = CalendarDate.parse(_text(json, 'to')),
      startUtc = DateTime.parse(_text(json, 'startUtc')),
      endUtc = DateTime.parse(_text(json, 'endUtc')),
      branchId = json['branchId'] as String? {
    if (from.compareTo(to) > 0 ||
        !startUtc.isUtc ||
        !endUtc.isUtc ||
        !startUtc.isBefore(endUtc)) {
      throw const FormatException('Invalid dashboard period.');
    }
  }
  final String timezone;
  final CalendarDate from;
  final CalendarDate to;
  final DateTime startUtc;

  /// Exclusive UTC bound resolved by the backend from inclusive local dates.
  final DateTime endUtc;
  final String? branchId;
}

class ProfileMetrics {
  ProfileMetrics.fromJson(Map<String, dynamic> json)
    : total = _count(json, 'total'),
      active = _count(json, 'active'),
      inactive = _count(json, 'inactive'),
      suspended = _count(json, 'suspended');
  final int total, active, inactive, suspended;
}

class SubscriptionMetrics {
  SubscriptionMetrics.fromJson(Map<String, dynamic> json)
    : currentlyActive = _count(json, 'currentlyActive'),
      expiringSoon = _count(json, 'expiringSoon'),
      expired = _count(json, 'expired');
  final int currentlyActive, expiringSoon, expired;
}

class PaymentMetrics {
  PaymentMetrics.fromJson(Map<String, dynamic> json)
    : periodSuccessfulAmountPaise = _count(json, 'periodSuccessfulAmountPaise'),
      periodSuccessfulCount = _count(json, 'periodSuccessfulCount'),
      outstandingAmountPaise = _count(json, 'outstandingAmountPaise');
  final int periodSuccessfulAmountPaise, periodSuccessfulCount;

  /// Current non-cancelled membership balances; independent of revenue dates.
  final int outstandingAmountPaise;
}

class AttendanceMetrics {
  AttendanceMetrics.fromJson(Map<String, dynamic> json)
    : periodVisits = _count(json, 'periodVisits'),
      periodUniqueMembers = _count(json, 'periodUniqueMembers'),
      currentlyCheckedIn = _count(json, 'currentlyCheckedIn');
  final int periodVisits, periodUniqueMembers, currentlyCheckedIn;
}

class GymDashboard {
  GymDashboard.fromJson(Map<String, dynamic> json)
    : period = DashboardPeriod.fromJson(_object(json['period'])),
      members = ProfileMetrics.fromJson(_object(json['members'])),
      trainers = ProfileMetrics.fromJson(_object(json['trainers'])),
      subscriptions = SubscriptionMetrics.fromJson(
        _object(json['subscriptions']),
      ),
      payments = PaymentMetrics.fromJson(_object(json['payments'])),
      attendance = AttendanceMetrics.fromJson(_object(json['attendance']));
  final DashboardPeriod period;
  final ProfileMetrics members, trainers;
  final SubscriptionMetrics subscriptions;
  final PaymentMetrics payments;
  final AttendanceMetrics attendance;
  bool get isEmpty =>
      members.total == 0 &&
      trainers.total == 0 &&
      subscriptions.currentlyActive == 0 &&
      subscriptions.expiringSoon == 0 &&
      subscriptions.expired == 0 &&
      payments.periodSuccessfulAmountPaise == 0 &&
      payments.periodSuccessfulCount == 0 &&
      payments.outstandingAmountPaise == 0 &&
      attendance.periodVisits == 0 &&
      attendance.periodUniqueMembers == 0 &&
      attendance.currentlyCheckedIn == 0;
}
