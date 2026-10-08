import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/attendance/models/attendance_models.dart';
import 'attendance_fakes.dart';

void main() {
  test('M16 open has nullable checkout/duration and scope', () {
    final visit = AttendanceVisit.fromJson(visitJson());
    expect(visit.status, VisitStatus.open);
    expect(visit.checkOutAt, isNull);
    expect(visit.durationMs, isNull);
    expect(visit.gymId, isNotNull);
    expect(visit.memberName, isNull);
    expect(visit.checkInAt.isUtc, isTrue);
  });
  test('M19 completed has safe display fields and server duration', () {
    final visit = AttendanceVisit.fromJson(
      visitJson(display: true, completed: true),
    );
    expect(visit.gymId, isNull);
    expect(visit.memberName, 'Alex River');
    expect(visit.branchName, 'Main');
    expect(visit.durationMs, 4500000);
    expect(formatVisitDuration(visit.durationMs!), '1h 15m 0s');
  });
  test('today preserves server day/timezone, summary and pagination', () {
    final day = AttendanceToday.fromResponse(todayJson(), {
      'pagination': {'page': 2, 'limit': 20, 'total': 1},
    });
    expect(day.date.toString(), '2026-10-08');
    expect(day.timezone, 'America/New_York');
    expect(day.summary.completed, 1);
    expect(day.pagination.page, 2);
  });
  test('empty today retains zero summary', () {
    final day = AttendanceToday.fromResponse(todayJson(empty: true), {
      'pagination': {'page': 1, 'limit': 20, 'total': 0},
    });
    expect(day.visits, isEmpty);
    expect(day.summary.total, 0);
  });
  for (final mutation in [
    {'durationMs': -1},
    {'status': 'open', 'checkOutAt': '2026-10-08T05:00:00Z'},
    {'status': 'completed'},
    {'checkInAt': 'not-a-time'},
  ]) {
    test(
      'invalid lifecycle $mutation is rejected',
      () => expect(
        () => AttendanceVisit.fromJson({...visitJson(), ...mutation}),
        throwsA(isA<Exception>()),
      ),
    );
  }
  test(
    'query respects status/member/page contract, never sends local dates',
    () {
      expect(
        AttendanceQuery(
          page: 2,
          status: VisitStatus.completed,
          memberId: '000000000000000000000011',
        ).toParameters(),
        {
          'page': '2',
          'limit': '20',
          'status': 'completed',
          'memberId': '000000000000000000000011',
        },
      );
      for (final page in [0, 10001]) {
        expect(() => AttendanceQuery(page: page), throwsFormatException);
      }
      expect(
        () => AttendanceQuery(status: VisitStatus.cancelled),
        throwsFormatException,
      );
      expect(
        () => AttendanceQuery(memberId: '../other'),
        throwsFormatException,
      );
    },
  );
  test(
    'timestamp formatting preserves the instant and labels device timezone',
    () {
      final instant = DateTime.parse('2026-10-08T04:00:00Z');
      expect(
        formatVisitTime(instant),
        endsWith(instant.toLocal().timeZoneName),
      );
      expect(instant.toIso8601String(), '2026-10-08T04:00:00.000Z');
      expect(formatVisitDuration(999), '0h 0m 0s');
    },
  );
}
