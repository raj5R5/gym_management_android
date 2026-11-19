import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_overview.dart';
import 'package:gym_management_app/features/members/presentation/member_overview_widgets.dart';
import 'package:gym_management_app/shared/contact/member_contact.dart';

Map<String, dynamic> row({
  Map<String, dynamic>? membership,
  int balance = 0,
  String? due,
}) => {
  'member': {
    'id': '000000000000000000000011',
    'memberCode': 'IT001',
    'firstName': 'Aarav',
    'lastName': 'Sharma',
    'phone': '98765 43210',
    'status': 'active',
  },
  'membership': membership,
  'balancePaise': balance,
  'dueSubscriptionId': due,
};

Map<String, dynamic> membership(
  String state, {
  int daysLeft = 0,
  int since = 0,
  bool expiring = false,
}) => {
  'state': state,
  'subscriptionId': 'sub-1',
  'planName': 'Monthly',
  'membershipPlanId': 'plan-1',
  'startDate': '2026-10-18',
  'endDate': '2026-11-17',
  'daysLeft': daysLeft,
  'daysSinceExpiry': since,
  'expiringSoon': expiring,
  'renewedAhead': false,
};

void main() {
  group('server-computed membership states', () {
    test('active, expiring, upcoming and expired labels', () {
      final active = MemberOverviewRow.fromJson(
        row(membership: membership('active', daysLeft: 3, expiring: true)),
      );
      expect(active.membership!.statusLabel, '3 days left');
      expect(active.membership!.usedFraction, closeTo(0.9, 0.001));
      expect(overviewActionFor(active), OverviewAction.renew);

      expect(
        MemberOverviewRow.fromJson(
          row(membership: membership('active', daysLeft: 1)),
        ).membership!.statusLabel,
        'Last day today',
      );
      expect(
        MemberOverviewRow.fromJson(
          row(membership: membership('upcoming', daysLeft: 30)),
        ).membership!.statusLabel,
        'Starts soon',
      );
      final expired = MemberOverviewRow.fromJson(
        row(membership: membership('expired', since: 10)),
      );
      expect(expired.membership!.statusLabel, 'Expired 10 days ago');
      expect(overviewActionFor(expired), OverviewAction.renew);
    });

    test('dues take priority and point at the unpaid membership', () {
      final owing = MemberOverviewRow.fromJson(
        row(
          membership: membership('expired', since: 3),
          balance: 50000,
          due: 'sub-0',
        ),
      );
      expect(overviewActionFor(owing), OverviewAction.collect);
      expect(owing.dueSubscriptionId, 'sub-0');
      final none = MemberOverviewRow.fromJson(row());
      expect(none.membership, isNull);
      expect(overviewActionFor(none), OverviewAction.addPlan);
      final paid = MemberOverviewRow.fromJson(
        row(membership: membership('active', daysLeft: 20)),
      );
      expect(overviewActionFor(paid), OverviewAction.none);
    });

    test('a balance without its membership id is rejected', () {
      expect(
        () => MemberOverviewRow.fromJson(row(balance: 100)),
        throwsFormatException,
      );
    });

    test('queries send only the server parameters', () {
      expect(
        const MemberOverviewQuery(
          filter: MemberOverviewFilter.dues,
          search: ' raj ',
          page: 2,
        ).toParameters(),
        {'filter': 'dues', 'page': '2', 'limit': '20', 'search': 'raj'},
      );
    });
  });

  group('contact links', () {
    test('Indian mobiles get the 91 prefix; full numbers stay', () {
      expect(whatsappNumber('98765 43210'), '919876543210');
      expect(whatsappNumber('098765-43210'), '919876543210');
      expect(whatsappNumber('+91 98765 43210'), '919876543210');
      expect(whatsappNumber('+44 7700 900123'), '447700900123');
      expect(whatsappNumber('12345'), isNull);
    });

    test('WhatsApp link carries the drafted text', () {
      final uri = whatsappUri('9876543210', 'Hi Aarav');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      expect(uri.queryParameters['text'], 'Hi Aarav');
      expect(callUri('+91 98765-43210').toString(), 'tel:+919876543210');
    });

    test('reminder drafts match the member situation', () {
      final expiring = MemberOverviewRow.fromJson(
        row(membership: membership('active', daysLeft: 3, expiring: true)),
      );
      expect(
        overviewReminder(expiring, 'Iron Gym'),
        'Hi Aarav, your Monthly membership ends in 3 days. '
        'Renew now to keep training without a break.\n– Iron Gym',
      );
      final owing = MemberOverviewRow.fromJson(
        row(
          membership: membership('active', daysLeft: 20),
          balance: 150000,
          due: 'sub-1',
        ),
      );
      expect(overviewReminder(owing, ''), contains('₹1,500 is pending'));
      final expired = MemberOverviewRow.fromJson(
        row(membership: membership('expired', since: 4)),
      );
      expect(overviewReminder(expired, ''), contains('has ended'));
    });
  });
}
