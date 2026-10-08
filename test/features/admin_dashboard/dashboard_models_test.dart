import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/shared/formatting/inr.dart';

import 'dashboard_fakes.dart';

void main() {
  test('parses every M18 dashboard section and authoritative period', () {
    final result = GymDashboard.fromJson(dashboardJson());
    expect(result.members.total, 12);
    expect(result.members.active, 9);
    expect(result.members.inactive, 2);
    expect(result.members.suspended, 1);
    expect(result.trainers.total, 3);
    expect(result.subscriptions.currentlyActive, 8);
    expect(result.subscriptions.expiringSoon, 2);
    expect(result.subscriptions.expired, 4);
    expect(result.payments.periodSuccessfulAmountPaise, 123456789);
    expect(result.payments.periodSuccessfulCount, 5);
    expect(result.attendance.periodVisits, 20);
    expect(result.attendance.periodUniqueMembers, 10);
    expect(result.attendance.currentlyCheckedIn, 2);
    expect(result.period.timezone, 'Asia/Kolkata');
    expect(result.period.startUtc, DateTime.utc(2026, 2, 28, 18, 30));
    expect(result.period.endUtc, DateTime.utc(2026, 3, 1, 18, 30));
    expect(result.period.branchId, isNull);
    expect(result.isEmpty, isFalse);
  });
  test('all zero metrics are a valid empty response', () {
    expect(GymDashboard.fromJson(dashboardJson(empty: true)).isEmpty, isTrue);
  });
  for (final value in [-1, 1.5, '123', null, 9007199254740992]) {
    test('rejects invalid money/count $value', () {
      final json = dashboardJson();
      json['payments'] = Map<String, dynamic>.from(json['payments'] as Map)
        ..['periodSuccessfulAmountPaise'] = value;
      expect(() => GymDashboard.fromJson(json), throwsFormatException);
    });
  }
  test('missing section is rejected instead of inventing zeros', () {
    expect(
      () => GymDashboard.fromJson(dashboardJson()..remove('attendance')),
      throwsFormatException,
    );
  });
  for (final date in [
    '2026-02-30',
    '2026-2-01',
    '2026-01-01T00:00:00Z',
    '0000-01-01',
  ]) {
    test(
      'rejects invalid calendar date $date',
      () => expect(() => CalendarDate.parse(date), throwsFormatException),
    );
  }
  test('inclusive 366-day leap year accepted; 367 rejected', () {
    final from = CalendarDate(2024, 1, 1);
    expect(
      DashboardQuery.range(from, CalendarDate(2024, 12, 31)).toParameters(),
      {'from': '2024-01-01', 'to': '2024-12-31'},
    );
    expect(
      () => DashboardQuery.range(from, CalendarDate(2025, 1, 1)),
      throwsFormatException,
    );
    expect(
      () => DashboardQuery.range(
        CalendarDate(2026, 3, 2),
        CalendarDate(2026, 3, 1),
      ),
      throwsFormatException,
    );
  });
  test(
    'today omits dates and branch; single-day range uses exact calendar values',
    () {
      expect(const DashboardQuery.today().toParameters(), isEmpty);
      final date = CalendarDate.fromPicker(DateTime(2026, 3, 1, 23));
      expect(DashboardQuery.range(date, date).toParameters(), {
        'from': '2026-03-01',
        'to': '2026-03-01',
      });
    },
  );
  for (final entry in {
    0: '₹0.00',
    1: '₹0.01',
    99: '₹0.99',
    100: '₹1.00',
    123456789: '₹12,34,567.89',
    9007199254740991: '₹9,00,71,99,25,47,409.91',
  }.entries) {
    test(
      'formats integer paise ${entry.key} exactly',
      () => expect(formatInrPaise(entry.key), entry.value),
    );
  }
  test(
    'rejects negative INR',
    () => expect(() => formatInrPaise(-1), throwsArgumentError),
  );
}
