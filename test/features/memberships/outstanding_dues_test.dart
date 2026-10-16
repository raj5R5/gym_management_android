import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/data/outstanding_dues_repository.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'payment_fakes.dart';

void main() {
  test(
    'only positive non-cancelled balances; current/history deduplication and expired debt',
    () async {
      final members = DueMembersFake()
        ..debts[memberId] = [
          debtJson(),
          debtJson(id: gymB, balance: 70000, status: 'expired'),
          debtJson(id: gymA, balance: 90000, status: 'cancelled'),
          debtJson(id: '000000000000000000000099', balance: 0),
        ];
      final dues = await OutstandingDuesRepository(
        members,
      ).load(gymA, current: () => true);
      expect(dues.members.single.memberships, hasLength(2));
      expect(dues.totalPaise, 120000);
    },
  );
  test(
    'walks all member and membership pages before displaying a total',
    () async {
      final members = DueMembersFake();
      members.profiles = List.generate(
        101,
        (i) => MemberProfile.fromJson(
          profileJson()..['id'] = (i + 1000).toRadixString(16).padLeft(24, '0'),
        ),
      );
      members.debts = {
        for (final member in members.profiles)
          member.id: [
            for (int i = 0; i < 21; i++)
              debtJson(
                id: (i + 3000).toRadixString(16).padLeft(24, '0'),
                balance: 1,
              ),
          ],
      };
      final result = await OutstandingDuesRepository(
        members,
      ).load(gymA, current: () => true);
      expect(members.listCalls, hasLength(2));
      expect(members.operations, hasLength(202));
      expect(result.totalPaise, 2121);
    },
  );
  test('search name/phone/plan and default highest-debt sorting', () {
    final alex = MemberProfile.fromJson(profileJson());
    final zed = MemberProfile.fromJson(
      profileJson(firstName: 'Zed')..['id'] = gymB,
    );
    final dues = OutstandingDues([
      OutstandingMember(alex, [Membership.fromJson(debtJson(balance: 1))]),
      OutstandingMember(zed, [Membership.fromJson(debtJson(balance: 50000))]),
    ]);
    expect(dues.search('').first.member.name, 'Zed River');
    expect(
      dues.search('', highestFirst: false).first.member.name,
      'Alex River',
    );
    expect(dues.search('alex'), hasLength(1));
    expect(dues.search('987654'), hasLength(2));
    expect(dues.search('monthly'), hasLength(2));
    expect(dues.search('absent'), isEmpty);
  });
  test('zero/free/paid memberships produce an empty dues list', () async {
    final members = DueMembersFake()..debts[memberId] = [debtJson(balance: 0)];
    expect(
      (await OutstandingDuesRepository(
        members,
      ).load(gymA, current: () => true)).members,
      isEmpty,
    );
  });
  test(
    'inconsistent balance fails instead of showing a partial total',
    () async {
      final members = DueMembersFake();
      (members.debts[memberId]!.first['paymentSummary']
              as Map)['remainingBalancePaise'] =
          1;
      await expectLater(
        OutstandingDuesRepository(members).load(gymA, current: () => true),
        throwsA(isA<BillingFailure>()),
      );
    },
  );
  test('scope change prevents subsequent membership calls', () async {
    final members = DueMembersFake();
    var checks = 0;
    await expectLater(
      OutstandingDuesRepository(
        members,
      ).load(gymA, current: () => ++checks < 2),
      throwsA(isA<BillingFailure>()),
    );
    expect(members.operations, isEmpty);
  });
}
