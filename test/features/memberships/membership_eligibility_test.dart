import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/models/membership_eligibility.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import '../members/member_fakes.dart';

void main() {
  Membership record({String status = 'active', int? balance = 50000}) =>
      Membership.fromJson(
        subscriptionJson()..addAll({
          'status': status,
          'isCurrentlyActive': status == 'active',
          if (balance != null)
            'paymentSummary': {
              'totalSuccessfulPaidPaise': 150000 - balance,
              'remainingBalancePaise': balance,
            },
        }),
      );
  for (final balance in [null, 0, 50000]) {
    test(
      'server active lifecycle blocks another period regardless of balance $balance',
      () {
        final active = record(balance: balance);
        expect(blockingMembership([active]), same(active));
      },
    );
  }
  test('expired and cancelled periods do not block a new membership', () {
    expect(
      blockingMembership([
        record(status: 'expired'),
        record(status: 'cancelled'),
      ]),
      isNull,
    );
  });
  test(
    'expired unpaid balance is collectible but paid and cancelled balances are excluded',
    () {
      final expired = record(status: 'expired');
      expect(
        verifiedUnpaidMemberships([
          expired,
          record(balance: 0),
          record(status: 'cancelled'),
        ]),
        [expired],
      );
    },
  );
  test(
    'missing eligible balance prevents collection rather than inventing zero',
    () {
      expect(
        () => verifiedUnpaidMemberships([record(balance: null)]),
        throwsA(isA<BillingFailure>()),
      );
    },
  );
  test(
    'scheduled server active status also blocks purchase independent of device time',
    () {
      final scheduled = Membership.fromJson(
        subscriptionJson()..['isCurrentlyActive'] = false,
      );
      expect(blockingMembership([scheduled]), same(scheduled));
    },
  );
}
