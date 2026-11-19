import 'dart:async';
import 'package:dio/dio.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/data/payment_repository.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'billing_fakes.dart';

Map<String, dynamic> debtJson({
  String id = subscriptionId,
  int balance = 50000,
  String status = 'active',
}) => subscriptionJson()
  ..addAll({
    'id': id,
    'status': status,
    'isCurrentlyActive': status == 'active',
    'paymentSummary': {
      'totalSuccessfulPaidPaise': 150000 - balance,
      'remainingBalancePaise': balance,
    },
  });

class DueMembersFake extends FakeMemberRepository {
  Completer<MembersPage>? listGate;
  @override
  Future<MemberProfile> get(String gymId, String id) async {
    operations.add('get:$gymId:$id');
    if (failure != null) throw failure!;
    return profiles.firstWhere((member) => member.id == id);
  }

  @override
  Future<MemberProfile> update(
    String gymId,
    String id,
    MemberDraft draft,
  ) async {
    await super.update(gymId, id, draft);
    final saved = MemberProfile.fromJson({
      ...profileJson(gymId: gymId),
      ...draft.toJson(editing: true),
    });
    profiles = [
      for (final member in profiles) member.id == id ? saved : member,
    ];
    return saved;
  }

  List<MemberProfile> profiles = [MemberProfile.fromJson(profileJson())];
  Map<String, List<Map<String, dynamic>>> debts = {
    memberId: [debtJson()],
  };
  @override
  Future<MembersPage> list(String gymId, MemberListQuery query) async {
    listCalls.add((gymId: gymId, query: query));
    if (failure != null) throw failure!;
    if (listGate != null) return listGate!.future;
    return MembersPage(
      profiles.skip((query.page - 1) * query.limit).take(query.limit).toList(),
      Pagination.fromJson({
        'page': query.page,
        'limit': query.limit,
        'total': profiles.length,
      }),
    );
  }

  @override
  Future<MembershipHistory> memberships(
    String gymId,
    String id,
    int page,
  ) async {
    operations.add('memberships:$gymId:$id:$page');
    if (failure != null) throw failure!;
    if (historyGate != null) return historyGate!.future;
    final all = debts[id] ?? [];
    return MembershipHistory.fromResponse(
      {
        'member': {'id': id},
        'currentMembership': all.isEmpty ? null : all.first,
        'subscriptions': all.skip((page - 1) * 20).take(20).toList(),
      },
      {'page': page, 'limit': 20, 'total': all.length},
    );
  }

  @override
  Future<MembershipDetail> membership(
    String gymId,
    String id,
    String subscription,
  ) async {
    if (failure != null) throw failure!;
    final value = debts[id]!.firstWhere((row) => row['id'] == subscription);
    return MembershipDetail.fromJson({
      'subscription': value,
      'paymentSummary': value['paymentSummary'],
    });
  }

  void collect(PaymentCollection collection) {
    final value = debts[collection.memberId]!.firstWhere(
      (row) => row['id'] == collection.subscriptionId,
    );
    final summary = value['paymentSummary'] as Map;
    summary['totalSuccessfulPaidPaise'] += collection.body['amountPaise'];
    summary['remainingBalancePaise'] -= collection.body['amountPaise'];
  }
}

class FakePaymentRepository implements PaymentRepository {
  final collections = <PaymentCollection>[];
  final cancellationTokens = <CancelToken?>[];
  final ranges = <({String gymId, DashboardQuery range, int page})>[];
  Object? failure;
  Completer<RecordedPayment>? gate;
  void Function(PaymentCollection)? onCollection;
  bool empty = false;
  MemberProfile? revenueMember;
  MemberProfile Function()? memberLookup;
  String? transactionReference;
  Completer<RevenuePage>? revenueGate;
  int revenuePaise = 100000, count = 1;
  @override
  Future<RevenuePage> revenue(
    String gymId,
    DashboardQuery range,
    int page,
  ) async {
    ranges.add((gymId: gymId, range: range, page: page));
    if (failure != null) throw failure!;
    if (revenueGate != null) return revenueGate!.future;
    final period = (dashboardJson()['period'] as Map<String, dynamic>)
      ..['from'] = range.from.toString()
      ..['to'] = range.to.toString()
      ..['startUtc'] = range.from!.value
          .subtract(const Duration(hours: 5, minutes: 30))
          .toIso8601String()
      ..['endUtc'] = range.to!.value
          .add(const Duration(days: 1))
          .subtract(const Duration(hours: 5, minutes: 30))
          .toIso8601String();
    return RevenuePage(
      empty
          ? []
          : [
              RevenueTransaction(
                RecordedPayment.fromJson(
                  paymentJson()
                    ..['transactionReference'] = transactionReference
                    ..['amountPaise'] = revenuePaise
                    ..['paidAt'] = range.from!.value
                        .add(const Duration(hours: 12))
                        .toIso8601String(),
                ),
                memberLookup?.call() ??
                    revenueMember ??
                    MemberProfile.fromJson(profileJson()),
              ),
            ],
      pagination(page, empty ? 0 : count),
      DashboardPeriod.fromJson(period),
      empty ? 0 : revenuePaise,
      empty ? 0 : count,
    );
  }

  @override
  Future<RecordedPayment> record(
    String gymId,
    PaymentCollection collection, {
    CancelToken? cancelToken,
  }) async {
    collections.add(collection);
    cancellationTokens.add(cancelToken);
    if (gate != null) return gate!.future;
    if (failure != null) throw failure!;
    onCollection?.call(collection);
    return confirmation(collection);
  }

  RecordedPayment confirmation(PaymentCollection collection) =>
      RecordedPayment.fromJson(
        paymentJson()..addAll({
          'memberId': collection.memberId,
          'subscriptionId': collection.subscriptionId,
          'amountPaise': collection.body['amountPaise'],
          'paymentMethod': collection.body['paymentMethod'],
          'paidAt': collection.body['paidAt'],
          'transactionReference': collection.body['transactionReference'],
        }),
      );
}
