import '../models/dashboard_models.dart';

const _months = [
  'JANUARY',
  'FEBRUARY',
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUGUST',
  'SEPTEMBER',
  'OCTOBER',
  'NOVEMBER',
  'DECEMBER',
];

String dashboardDateRangeLabel(CalendarDate from, CalendarDate to) {
  String date(CalendarDate value) {
    final month = _months[value.value.month - 1];
    return '${value.value.day} ${month[0]}${month.substring(1, 3).toLowerCase()} ${value.value.year.toString().padLeft(4, '0')}';
  }

  return from.compareTo(to) == 0 ? date(from) : '${date(from)} – ${date(to)}';
}

/// Display only: calendar labels have already been resolved in the gym timezone
/// by the backend. Never infer business "today" from the phone's local clock.
String revenuePeriodLabel(DashboardPeriod period, {required bool gymToday}) {
  final from = period.from.value;
  final to = period.to.value;
  String month(DateTime value) => _months[value.month - 1].substring(0, 3);
  String date(DateTime value) =>
      '${value.day} ${month(value)} ${value.year.toString().padLeft(4, '0')}';
  if (period.from.compareTo(period.to) == 0) {
    return '${gymToday ? 'TODAY · ' : ''}${date(from)}';
  }
  if (from.year == to.year && from.month == to.month) {
    if (from.day == 1 && to.day == DateTime.utc(to.year, to.month + 1, 0).day) {
      // A selected historical month is not necessarily the current month.
      return 'MONTH · ${_months[from.month - 1]} ${from.year.toString().padLeft(4, '0')}';
    }
    return '${from.day}–${date(to)}';
  }
  if (from.year == to.year) return '${from.day} ${month(from)} – ${date(to)}';
  return '${date(from)} – ${date(to)}';
}
