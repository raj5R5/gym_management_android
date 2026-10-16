import 'package:dio/dio.dart';
import 'package:gym_management_app/features/memberships/data/renewal_repository.dart';
import 'package:gym_management_app/features/memberships/models/renewal_operation.dart';
import 'package:gym_management_app/features/memberships/models/renewal_preview.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import '../members/member_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'billing_fakes.dart';

Map<String, dynamic> renewalResultJson(
  RenewalOperationRequest request, {
  String gymId = gymA,
  String id = memberId,
  String predecessor = subscriptionId,
}) {
  final body = request.body;
  final terms = body['expectedTerms'] as Map<String, dynamic>;
  final received = request.receivedPaise;
  final payment = body['payment'] as Map<String, dynamic>?;
  const newId = '000000000000000000000088';
  return {
    'subscription': {
      ...fullSubscription(),
      'id': newId,
      'gymId': gymId,
      'memberId': id,
      'membershipPlanId': body['planId'],
      'previousSubscriptionId': predecessor,
      'planNameSnapshot': terms['planName'],
      'durationDaysSnapshot': terms['durationDays'],
      'pricePaiseSnapshot': request.pricePaise,
      'startDate': terms['startDate'],
      'endDate': terms['endDate'],
    },
    'payment': payment == null
        ? null
        : {
            ...paymentJson(),
            'gymId': gymId,
            'memberId': id,
            'subscriptionId': newId,
            'amountPaise': received,
            'paymentMethod': payment['method'],
            'paidAt': payment['paidAt'],
            'transactionReference': payment['reference'],
          },
    'billing': {
      'planPricePaise': request.pricePaise,
      'amountReceivedPaise': received,
      'outstandingBalancePaise': request.balancePaise,
    },
  };
}

class FakeRenewalRepository implements RenewalRepository {
  FakeRenewalRepository([FakeMembershipRepository? billing])
    : billing = billing ?? FakeMembershipRepository();
  final FakeMembershipRepository billing;
  final requests = <RenewalOperationRequest>[];
  final committed = <String, RenewalResult>{};
  bool loseResponse = false;
  void Function(RenewalOperationRequest)? beforeComplete;
  int insertions = 0;
  @override
  Future<RenewalPreview> preview(
    String gymId,
    String id,
    String predecessor,
    String selectedPlan,
  ) async {
    billing.operations.add('renewal-preview');
    if (billing.previewFailure != null) throw billing.previewFailure!;
    if (billing.failure != null) throw billing.failure!;
    if (billing.previewGate != null) return billing.previewGate!.future;
    final plan = [
      ...billing.extraPlans,
      billing.savedPlan ?? planJson(),
    ].firstWhere((p) => p['id'] == selectedPlan);
    final start = DateTime.utc(2026, 3, 31);
    final end = start
        .add(Duration(days: plan['durationDays'] as int))
        .toIso8601String()
        .substring(0, 10);
    return RenewalPreview.fromJson({
      ...renewalPreviewJson(),
      'terms': {
        'planName': plan['name'],
        'durationDays': plan['durationDays'],
        'pricePaise': plan['price'],
        'startDate': '2026-03-31',
        'endDate': end,
      },
      'outstandingBalancePaise': plan['price'],
      ...?billing.previewJson,
      'gymId': gymId,
      'planId': selectedPlan,
    });
  }

  @override
  Future<RenewalResult> complete(
    String gymId,
    String id,
    String predecessor,
    RenewalOperationRequest request, {
    CancelToken? cancelToken,
  }) async {
    beforeComplete?.call(request);
    requests.add(request);
    billing.operations.add('renew');
    billing.renewals.add(
      RenewalPreview.fromJson({
        ...renewalPreviewJson(),
        'planId': request.body['planId'],
        'terms': request.body['expectedTerms'],
        'outstandingBalancePaise': request.pricePaise,
      }),
    );
    if (committed[request.key] case final previous?) return previous;
    if (billing.failure != null) throw billing.failure!;
    if (billing.writeGate != null) await billing.writeGate!.future;
    final result = RenewalResult.fromJson(
      renewalResultJson(
        request,
        gymId: gymId,
        id: id,
        predecessor: predecessor,
      ),
    );
    insertions++;
    committed[request.key] = result;
    if (loseResponse) {
      throw const BillingFailure('Response lost.', uncertain: true);
    }
    return result;
  }
}
