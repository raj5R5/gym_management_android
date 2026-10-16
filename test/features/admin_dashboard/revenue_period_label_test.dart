import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/revenue_period_label.dart';

void main() {
  DashboardPeriod period(String from, String to) => DashboardPeriod.fromJson({
    'timezone': 'UTC',
    'from': from,
    'to': to,
    'startUtc': '${from}T00:00:00.000Z',
    'endUtc': CalendarDate.parse(
      to,
    ).value.add(const Duration(days: 1)).toIso8601String(),
  });
  test(
    'today label uses gym calendar date even when UTC boundary falls on previous day',
    () {
      final response = DashboardPeriod.fromJson({
        'timezone': 'Pacific/Kiritimati',
        'from': '2026-10-12',
        'to': '2026-10-12',
        'startUtc': '2026-10-11T10:00:00.000Z',
        'endUtc': '2026-10-12T10:00:00.000Z',
      });
      expect(
        revenuePeriodLabel(response, gymToday: true),
        'TODAY · 12 OCT 2026',
      );
    },
  );
  test('selected single historical date never claims to be today', () {
    expect(
      revenuePeriodLabel(period('2026-10-10', '2026-10-10'), gymToday: false),
      '10 OCT 2026',
    );
  });
  for (final entry in {
    ('2026-10-01', '2026-10-31'): 'MONTH · OCTOBER 2026',
    ('2024-02-01', '2024-02-29'): 'MONTH · FEBRUARY 2024',
    ('2026-02-01', '2026-02-28'): 'MONTH · FEBRUARY 2026',
    ('2026-10-10', '2026-10-12'): '10–12 OCT 2026',
    ('2026-09-30', '2026-10-12'): '30 SEP – 12 OCT 2026',
    ('2025-12-31', '2026-01-02'): '31 DEC 2025 – 2 JAN 2026',
  }.entries) {
    test('labels exact inclusive range ${entry.key}', () {
      expect(
        revenuePeriodLabel(period(entry.key.$1, entry.key.$2), gymToday: false),
        entry.value,
      );
    });
  }
  test(
    'active calendar labels show exact dates including single days and year boundaries',
    () {
      expect(
        dashboardDateRangeLabel(
          CalendarDate(2026, 10, 10),
          CalendarDate(2026, 10, 12),
        ),
        '10 Oct 2026 – 12 Oct 2026',
      );
      expect(
        dashboardDateRangeLabel(
          CalendarDate(2026, 10, 10),
          CalendarDate(2026, 10, 10),
        ),
        '10 Oct 2026',
      );
      expect(
        dashboardDateRangeLabel(
          CalendarDate(2025, 12, 31),
          CalendarDate(2026, 1, 1),
        ),
        '31 Dec 2025 – 1 Jan 2026',
      );
    },
  );
}
