import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/formatting/payment_date.dart';

void main() {
  const dates = DefaultMaterialLocalizations();
  test('gym timezone crosses midnight without changing the saved instant', () {
    final paidAt = DateTime.utc(2026, 3, 1, 20, 30, 12, 123);
    final original = paidAt.toIso8601String();
    expect(
      formatPaymentDateTime(dates, paidAt, timezone: 'Asia/Kolkata'),
      'Mar 2, 2026 · 2:00 AM · Asia/Kolkata',
    );
    expect(paidAt.toIso8601String(), original);
  });
  test('UTC is readable and includes the year and time', () {
    expect(
      formatPaymentDateTime(
        dates,
        DateTime.utc(2026, 3, 1, 20, 30),
        timezone: 'UTC',
      ),
      'Mar 1, 2026 · 8:30 PM · UTC',
    );
  });
  test('DST is calculated at each payment instant, not the range boundary', () {
    expect(
      formatPaymentDateTime(
        dates,
        DateTime.utc(2026, 3, 8, 6, 30),
        timezone: 'America/New_York',
      ),
      'Mar 8, 2026 · 1:30 AM · America/New_York',
    );
    expect(
      formatPaymentDateTime(
        dates,
        DateTime.utc(2026, 3, 8, 7, 30),
        timezone: 'America/New_York',
      ),
      'Mar 8, 2026 · 3:30 AM · America/New_York',
    );
  });
  for (final zone in [null, 'Unsupported/Zone']) {
    test('unavailable timezone $zone explicitly falls back to UTC', () {
      expect(
        formatPaymentDateTime(dates, DateTime.utc(2026, 1, 1), timezone: zone),
        'Jan 1, 2026 · 12:00 AM · UTC (gym timezone unavailable)',
      );
    });
  }
  test('legacy IANA aliases remain supported', () {
    expect(
      formatPaymentDateTime(
        dates,
        DateTime.utc(2026, 1, 1),
        timezone: 'Asia/Calcutta',
      ),
      'Jan 1, 2026 · 5:30 AM · Asia/Calcutta',
    );
  });
}
