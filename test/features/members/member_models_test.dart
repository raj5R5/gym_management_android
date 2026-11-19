import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'member_fakes.dart';

void main() {
  test(
    'UI gender query preserves pagination without unsupported API parameters',
    () {
      final query = MemberListQuery(
        search: ' Alex ',
        gender: 'male',
      ).withPage(2);
      expect(query.gender, 'male');
      expect(query.toParameters(), {
        'page': '2',
        'limit': '20',
        'search': 'Alex',
      });
      expect(
        () => MemberListQuery(gender: 'unsupported'),
        throwsFormatException,
      );
      expect(MemberListQuery(gender: 'female').gender, 'female');
    },
  );
  test('member profile required fields and absent optional fields', () {
    final member = MemberProfile.fromJson(profileJson());
    expect(member.name, 'Alex River');
    expect(member.memberCode, 'ME01');
    expect(member.status, MemberStatus.active);

    expect(member.address, isNull);
    expect(member.gender, isNull);
  });
  test('profile optional fields and nulls parse exactly', () {
    final json = profileJson()
      ..addAll({
        'branchId': null,
        'gender': 'other',
        'dateOfBirth': '2000-01-01',
        'address': {'line1': 'Road', 'city': 'City', 'countryCode': 'IN'},
        'emergencyContact': {'name': 'Pat', 'phone': '9876543211'},
      });
    final member = MemberProfile.fromJson(json);
    expect(member.dateOfBirth.toString(), '2000-01-01');
    expect(member.address!.display, 'Road, City, IN');
    expect(member.emergencyContact!.relationship, isNull);
  });
  test(
    'empty member summary preserves null current membership and zero totals',
    () {
      final summary = MemberSummary.fromJson(summaryJson());
      expect(summary.member.gymId, isNull);

      expect(summary.currentSubscription, isNull);
      expect(summary.currentPayments, isNull);
      expect(summary.history, isEmpty);
      expect(summary.historyPagination.total, 0);
      expect(summary.payments.totalPaise, 0);
    },
  );
  test(
    'complete summary parses snapshots, balances, attendance and trainers',
    () {
      final summary = MemberSummary.fromJson(summaryJson(populated: true));

      expect(summary.trainers.single.name, 'Pat Lee');
      expect(summary.currentSubscription!.pricePaise, 150000);
      expect(summary.currentSubscription!.endDate.toString(), '2026-03-31');
      expect(summary.currentPayments!.balancePaise, 149697);
      expect(summary.payments.latest!.amountPaise, 202);
    },
  );
  test('membership history and cancellation detail parsing', () {
    final history = MembershipHistory.fromResponse(
      historyJson(populated: true),
      {'page': 1, 'limit': 20, 'total': 21},
    );
    expect(history.pagination.hasNext, isTrue);
    expect(history.subscriptions.single.payments!.paidPaise, 303);
    final detail = MembershipDetail.fromJson({
      'subscription': subscriptionJson(cancelled: true)
        ..['cancelledAt'] = '2026-03-03T12:00:00Z'
        ..['cancellationReason'] = 'Requested',
      'paymentSummary': {
        'totalSuccessfulPaidPaise': 303,
        'remainingBalancePaise': 149697,
      },
    });
    expect(detail.subscription.status, 'cancelled');
    expect(detail.subscription.cancelledAt!.isUtc, isTrue);
    expect(detail.subscription.cancellationReason, 'Requested');
  });
  for (final page in [0, 10001]) {
    test(
      'pagination rejects page $page',
      () => expect(
        () => Pagination.fromJson({'page': page, 'limit': 20, 'total': 0}),
        throwsFormatException,
      ),
    );
  }
  for (final limit in [0, 101]) {
    test(
      'pagination rejects limit $limit',
      () => expect(() => MemberListQuery(limit: limit), throwsFormatException),
    );
  }
  test(
    'last permitted page never exceeds backend maximum',
    () => expect(
      Pagination.fromJson({'page': 10000, 'limit': 1, 'total': 20000}).hasNext,
      isFalse,
    ),
  );
  test('malformed member and missing summary sections fail closed', () {
    expect(
      () => MemberProfile.fromJson(profileJson()..remove('phone')),
      throwsFormatException,
    );
    expect(
      () => MemberSummary.fromJson(summaryJson()..remove('paymentSummary')),
      throwsFormatException,
    );
  });
  for (final money in [-1, 1.5, '303', 9007199254740992]) {
    test('invalid monetary value $money fails parsing', () {
      final json = summaryJson();
      json['paymentSummary'] = {
        'totalSuccessfulAmountPaise': money,
        'successfulPaymentCount': 0,
        'latestSuccessfulPayment': null,
      };
      expect(() => MemberSummary.fromJson(json), throwsFormatException);
    });
  }
  test('onboarding whitelist has no tenant, branch, user or status fields', () {
    expect(draft().toJson(editing: false), {
      'memberCode': 'ME01',
      'firstName': 'Alex',
      'lastName': 'River',
      'phone': '+91 9876543210',
    });
  });
  test(
    'PATCH excludes immutable code and clears absent optional profile fields',
    () {
      final json = draft().toJson(editing: true);
      expect(json.containsKey('memberCode'), isFalse);
      expect(json['address'], isNull);
      expect(json.containsKey('branchId'), isFalse);
      expect(json.containsKey('userId'), isFalse);
    },
  );
  test('input validators match accepted code, name, phone and date syntax', () {
    expect(validateMemberCode(' me_01 '), isNull);
    expect(validateMemberCode('x'), isNotNull);
    expect(validateName('  '), isNotNull);
    expect(validatePhone('123'), isNotNull);
    expect(validatePhone('+91 (98765) 43210'), isNull);
    expect(validateBirthDate('2026-02-30'), isNotNull);
    expect(validateBirthDate('9999-01-01'), isNotNull);
    expect(validateBirthDate(''), isNull);
  });
}
