import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/memberships/models/renewal_preview.dart';
import 'billing_fakes.dart';

void main() {
  test('preview uses current server terms and exact calendar dates', () {
    final preview = RenewalPreview.fromJson(renewalPreviewJson());
    expect(preview.memberName, 'Ada Lovelace');
    expect(preview.durationDays, 30);
    expect(preview.pricePaise, 150000);
    expect(preview.toRequest(), {
      'expectedTerms': renewalPreviewJson()['terms'],
    });
  });
  test('free renewal has zero initial payment and no new balance', () {
    final json = renewalPreviewJson();
    (json['terms'] as Map)['pricePaise'] = 0;
    json['outstandingBalancePaise'] = 0;
    final preview = RenewalPreview.fromJson(json);
    expect(preview.pricePaise, 0);
    expect(preview.initialPaymentPaise, 0);
  });
  for (final field in [
    'gymId',
    'subscriptionId',
    'planId',
    'calendarTimezone',
  ]) {
    test('rejects invalid $field', () {
      expect(
        () =>
            RenewalPreview.fromJson(renewalPreviewJson()..[field] = 'invalid'),
        throwsFormatException,
      );
    });
  }
  for (final entry in [
    ('durationDays', 0),
    ('durationDays', 3651),
    ('pricePaise', -1),
    ('pricePaise', 1.5),
    ('pricePaise', 1000000001),
    ('startDate', '2026-03-01'),
    ('endDate', '2026-03-31'),
    ('endDate', '2026-02-30'),
  ]) {
    test('rejects malformed terms ${entry.$1}=${entry.$2}', () {
      final json = renewalPreviewJson();
      (json['terms'] as Map)[entry.$1] = entry.$2;
      expect(() => RenewalPreview.fromJson(json), throwsFormatException);
    });
  }
  test('rejects inconsistent payment terms', () {
    expect(
      () => RenewalPreview.fromJson(
        renewalPreviewJson()..['initialPaymentPaise'] = 100,
      ),
      throwsFormatException,
    );
    expect(
      () => RenewalPreview.fromJson(
        renewalPreviewJson()..['outstandingBalancePaise'] = 100,
      ),
      throwsFormatException,
    );
  });
}
