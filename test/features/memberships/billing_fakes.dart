import 'dart:async';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/data/membership_repository.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';

const planId = '000000000000000000000033';
Map<String, dynamic> planJson() => {
  'id': planId,
  'gymId': gymA,
  'name': 'Monthly',
  'durationDays': 30,
  'price': 150000,
  'status': 'active',
  'description': null,
};
Map<String, dynamic> paymentJson() => {
  'id': '000000000000000000000066',
  'gymId': gymA,
  'memberId': memberId,
  'subscriptionId': subscriptionId,
  'amountPaise': 303,
  'status': 'succeeded',
  'paymentMethod': 'cash',
  'paidAt': '2026-03-02T12:00:00.000Z',
  'transactionReference': null,
  'recordedByUserId': null,
};
Map<String, dynamic> fullSubscription({bool cancelled = false}) =>
    subscriptionJson(cancelled: cancelled)
      ..addAll({'gymId': gymA, 'memberId': memberId});
BillingResult billingResult({
  ManualPayment? payment,
  bool cancelled = false,
  bool renewed = false,
}) => BillingResult(
  Membership.fromJson(
    fullSubscription(cancelled: cancelled)..addAll({
      if (cancelled) 'cancelledAt': '2026-03-03T12:00:00Z',
      if (cancelled) 'cancellationReason': 'Requested',
      if (renewed) 'id': '000000000000000000000088',
      if (renewed) 'previousSubscriptionId': subscriptionId,
    }),
  ),
  payment == null
      ? null
      : RecordedPayment.fromJson(
          paymentJson()..addAll({
            'amountPaise': payment.amountPaise,
            'paymentMethod': payment.method.wireValue,
            'paidAt': payment.paidAt.toIso8601String(),
            'transactionReference': payment.reference.isEmpty
                ? null
                : payment.reference,
          }),
        ),
);
Pagination pagination(int page, int total) =>
    Pagination.fromJson({'page': page, 'limit': 20, 'total': total});

class FakeMembershipRepository implements MembershipRepository {
  Object? failure;
  Map<String, dynamic>? savedPlan;
  final planWrites = <Map<String, dynamic>>[];
  bool empty = false;
  int total = 1;
  final operations = <String>[];
  final purchases = <PurchaseDraft>[];
  Completer<BillingResult>? writeGate;
  Completer<MembershipPlan>? planSaveGate;
  Completer<BillingPage<MembershipPlan>>? planGate;
  void _check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<BillingPage<MembershipPlan>> plans(String gymId, int page) async {
    operations.add('plans:$gymId:$page');
    _check();
    if (planGate != null) return planGate!.future;
    return BillingPage(
      empty
          ? []
          : [
              MembershipPlan.fromJson({
                ...?savedPlan,
                ...(savedPlan == null ? planJson() : <String, dynamic>{}),
                'gymId': gymId,
              }),
            ],
      pagination(page, empty ? 0 : total),
    );
  }

  @override
  Future<BillingPage<MembershipPlan>> managePlans(String gymId, int page) =>
      plans(gymId, page);
  @override
  Future<MembershipPlan> plan(String gymId, String planId) async {
    operations.add('plan:$planId');
    _check();
    return MembershipPlan.fromJson(savedPlan ?? planJson());
  }

  @override
  Future<MembershipPlan> savePlan(
    String gymId,
    PlanDraft draft, {
    String? planId,
  }) async {
    operations.add(planId == null ? 'create-plan' : 'update-plan');
    planWrites.add(draft.toJson(editing: planId != null));
    _check();
    savedPlan = {...planJson(), ...draft.toJson(editing: planId != null)};
    empty = false;
    if (planSaveGate != null) return planSaveGate!.future;
    return MembershipPlan.fromJson(savedPlan!);
  }

  @override
  Future<BillingPage<RecordedPayment>> payments(
    String gymId,
    String memberId,
    int page,
  ) async {
    operations.add('payments:$gymId:$memberId:$page');
    _check();
    return BillingPage(
      empty
          ? []
          : [
              RecordedPayment.fromJson(
                paymentJson()..addAll({'gymId': gymId, 'memberId': memberId}),
              ),
            ],
      pagination(page, empty ? 0 : total),
    );
  }

  @override
  Future<BillingResult> purchase(
    String gymId,
    String memberId,
    PurchaseDraft draft,
  ) async {
    operations.add('purchase');
    purchases.add(draft);
    _check();
    if (writeGate != null) return writeGate!.future;
    return billingResult(payment: draft.payment);
  }

  @override
  Future<BillingResult> cancel(
    String gymId,
    String memberId,
    String subscriptionId,
    String reason,
  ) async {
    operations.add('cancel:$reason');
    _check();
    return billingResult(cancelled: true);
  }

  @override
  Future<BillingResult> renew(
    String gymId,
    String memberId,
    String subscriptionId,
  ) async {
    operations.add('renew');
    _check();
    return billingResult(renewed: true);
  }
}

class ActiveMembershipMemberRepository extends FakeMemberRepository {
  @override
  Future<MembershipDetail> membership(
    String gymId,
    String id,
    String subId,
  ) async {
    operations.add('membership:$subId');
    if (failure != null) throw failure!;
    return MembershipDetail.fromJson({
      'subscription': fullSubscription(),
      'paymentSummary': {
        'totalSuccessfulPaidPaise': 303,
        'remainingBalancePaise': 149697,
      },
    });
  }
}
