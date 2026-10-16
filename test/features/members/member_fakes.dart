import 'dart:async';
import 'package:gym_management_app/features/members/data/member_repository.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';

const memberId = '000000000000000000000011';
const subscriptionId = '000000000000000000000022';
Map<String, dynamic> profileJson({
  String gymId = gymA,
  String firstName = 'Alex',
}) => {
  'id': memberId,
  'gymId': gymId,
  'memberCode': 'ME01',
  'firstName': firstName,
  'lastName': 'River',
  'phone': '+91 9876543210',
  'status': 'active',
};
Map<String, dynamic> subscriptionJson({bool cancelled = false}) => {
  'id': subscriptionId,
  'membershipPlanId': '000000000000000000000033',
  'planNameSnapshot': 'Monthly',
  'durationDaysSnapshot': 30,
  'pricePaiseSnapshot': 150000,
  'startDate': '2026-03-01',
  'endDate': '2026-03-31',
  'status': cancelled ? 'cancelled' : 'active',
  'isCurrentlyActive': !cancelled,
  'previousSubscriptionId': null,
};
Map<String, dynamic> summaryJson({bool populated = false}) => {
  'member': profileJson()..remove('gymId'),
  'currentBranch': populated
      ? {
          'id': '000000000000000000000044',
          'name': 'Central',
          'status': 'active',
        }
      : null,
  'currentTrainers': populated
      ? [
          {
            'trainerId': '000000000000000000000055',
            'trainerCode': 'TR01',
            'firstName': 'Pat',
            'lastName': 'Lee',
            'phone': '9876543211',
          },
        ]
      : [],
  'currentSubscription': populated ? subscriptionJson() : null,
  'subscriptionHistory': {
    'items': populated ? [subscriptionJson()] : [],
    'page': 1,
    'limit': 20,
    'total': populated ? 1 : 0,
  },
  'paymentSummary': {
    'totalSuccessfulAmountPaise': populated ? 303 : 0,
    'successfulPaymentCount': populated ? 2 : 0,
    'latestSuccessfulPayment': populated
        ? {
            'id': '000000000000000000000066',
            'subscriptionId': subscriptionId,
            'amountPaise': 202,
            'paymentMethod': 'cash',
            'paidAt': '2026-03-02T12:00:00Z',
          }
        : null,
  },
  'currentSubscriptionPaymentSummary': populated
      ? {
          'pricePaise': 150000,
          'paidAmountPaise': 303,
          'remainingAmountPaise': 149697,
          'paymentCount': 2,
        }
      : null,
  'attendanceSummary': {
    'totalCompletedVisits': populated ? 1 : 0,
    'latestAttendance': populated
        ? {
            'id': '000000000000000000000077',
            'branchId': '000000000000000000000044',
            'subscriptionId': subscriptionId,
            'checkInAt': '2026-03-01T10:00:00Z',
            'checkOutAt': '2026-03-01T11:00:00Z',
            'status': 'completed',
          }
        : null,
    'currentlyCheckedIn': false,
    'currentAttendance': null,
  },
};
Map<String, dynamic> historyJson({bool populated = false}) => {
  'member': {
    'id': memberId,
    'memberCode': 'ME01',
    'firstName': 'Alex',
    'lastName': 'River',
  },
  'currentMembership': populated
      ? (subscriptionJson()
          ..['paymentSummary'] = {
            'totalSuccessfulPaidPaise': 303,
            'remainingBalancePaise': 149697,
          })
      : null,
  'subscriptions': populated
      ? [
          subscriptionJson()
            ..['paymentSummary'] = {
              'totalSuccessfulPaidPaise': 303,
              'remainingBalancePaise': 149697,
            },
        ]
      : [],
};
MemberDraft draft({String firstName = 'Alex'}) => MemberDraft(
  memberCode: 'ME01',
  firstName: firstName,
  lastName: 'River',
  phone: '+91 9876543210',
);

class FakeMemberRepository implements MemberRepository {
  Object? failure;
  bool empty = false, populated = false;
  int total = 1;
  List<Map<String, dynamic>>? historyRecords;
  Completer<MembershipHistory>? historyGate;
  final listCalls = <({String gymId, MemberListQuery query})>[];
  final operations = <String>[];
  final writes = <Map<String, dynamic>>[];
  Completer<MemberProfile>? saveGate;
  final pendingLists = <Completer<MembersPage>>[];
  bool delayLists = false;
  void _check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<MembersPage> list(String gymId, MemberListQuery query) async {
    listCalls.add((gymId: gymId, query: query));
    _check();
    if (delayLists) {
      final pending = Completer<MembersPage>();
      pendingLists.add(pending);
      return pending.future;
    }
    return MembersPage(
      empty ? [] : [MemberProfile.fromJson(profileJson(gymId: gymId))],
      Pagination.fromJson({
        'page': query.page,
        'limit': query.limit,
        'total': empty ? 0 : total,
      }),
    );
  }

  @override
  Future<MemberProfile> get(String gymId, String id) async {
    operations.add('get:$gymId:$id');
    _check();
    return MemberProfile.fromJson(profileJson(gymId: gymId));
  }

  @override
  Future<MemberSummary> summary(String gymId, String id) async {
    operations.add('summary:$gymId:$id');
    _check();
    return MemberSummary.fromJson(summaryJson(populated: populated));
  }

  @override
  Future<MemberProfile> onboard(String gymId, MemberDraft draft) async {
    operations.add('onboard:$gymId');
    writes.add(draft.toJson(editing: false));
    _check();
    if (saveGate != null) return saveGate!.future;
    return MemberProfile.fromJson(
      profileJson(gymId: gymId, firstName: draft.firstName),
    );
  }

  @override
  Future<MemberProfile> update(
    String gymId,
    String id,
    MemberDraft draft,
  ) async {
    operations.add('update:$gymId:$id');
    writes.add(draft.toJson(editing: true));
    _check();
    if (saveGate != null) return saveGate!.future;
    return MemberProfile.fromJson(
      profileJson(gymId: gymId, firstName: draft.firstName),
    );
  }

  @override
  Future<MembershipHistory> memberships(
    String gymId,
    String id,
    int page,
  ) async {
    operations.add('history:$page');
    _check();
    if (historyGate != null) return historyGate!.future;
    final data = historyRecords == null
        ? historyJson(populated: populated)
        : {
            ...historyJson(),
            'subscriptions': historyRecords!
                .skip((page - 1) * 20)
                .take(20)
                .toList(),
          };
    return MembershipHistory.fromResponse(data, {
      'page': page,
      'limit': 20,
      'total': historyRecords?.length ?? (populated ? total : 0),
    });
  }

  @override
  Future<MembershipDetail> membership(
    String gymId,
    String id,
    String subId,
  ) async {
    operations.add('membership:$subId');
    _check();
    return MembershipDetail.fromJson({
      'subscription': subscriptionJson(cancelled: true)
        ..['cancelledAt'] = '2026-03-03T12:00:00Z'
        ..['cancellationReason'] = 'Requested',
      'paymentSummary': {
        'totalSuccessfulPaidPaise': 303,
        'remainingBalancePaise': 149697,
      },
    });
  }
}

/// Actual paginated member DTOs; gender filtering remains in the production provider.
class GenderMemberRepository extends FakeMemberRepository {
  final profiles = List.generate(
    125,
    (index) => MemberProfile.fromJson({
      ...profileJson(firstName: 'Person $index'),
      'id': index.toRadixString(16).padLeft(24, '0'),
      'memberCode': 'M$index',
      if (index % 3 != 2) 'gender': index % 3 == 0 ? 'male' : 'female',
    }),
  );
  @override
  Future<MembersPage> list(String gymId, MemberListQuery query) async {
    listCalls.add((gymId: gymId, query: query));
    if (failure != null) throw failure!;
    final found = profiles
        .where(
          (profile) =>
              query.search.isEmpty ||
              profile.name.toLowerCase().contains(query.search.toLowerCase()),
        )
        .toList();
    return MembersPage(
      found.skip((query.page - 1) * query.limit).take(query.limit).toList(),
      Pagination.fromJson({
        'page': query.page,
        'limit': query.limit,
        'total': found.length,
      }),
    );
  }
}

List<Map<String, dynamic>> expiredHistoryFixture() => [
  subscriptionJson()..addAll({
    'status': 'expired',
    'isCurrentlyActive': false,
    'paymentSummary': {
      'totalSuccessfulPaidPaise': 303,
      'remainingBalancePaise': 149697,
    },
  }),
];
