import 'package:dio/dio.dart';
import '../../members/data/member_repository.dart';
import '../../members/models/member_models.dart';
import '../models/billing_models.dart';
import 'billing_failure.dart';

abstract interface class MembershipRepository {
  Future<BillingPage<MembershipPlan>> managePlans(String gymId, int page);
  Future<MembershipPlan> plan(String gymId, String planId);
  Future<MembershipPlan> savePlan(
    String gymId,
    PlanDraft draft, {
    String? planId,
  });
  Future<BillingPage<MembershipPlan>> plans(String gymId, int page);
  Future<BillingPage<RecordedPayment>> payments(
    String gymId,
    String memberId,
    int page,
  );
  Future<BillingResult> purchase(
    String gymId,
    String memberId,
    PurchaseDraft draft,
  );
  Future<BillingResult> cancel(
    String gymId,
    String memberId,
    String subscriptionId,
    String reason,
  );
  Future<BillingResult> renew(
    String gymId,
    String memberId,
    String subscriptionId,
  );
}

class DioMembershipRepository implements MembershipRepository {
  DioMembershipRepository(this._client, this._members);
  final Dio _client;
  final MemberRepository _members;
  void _id(String id) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
      throw const BillingFailure('Invalid billing context.');
    }
  }

  String _gym(String gymId, [String? memberId, String? subscriptionId]) {
    _id(gymId);
    if (memberId != null) _id(memberId);
    if (subscriptionId != null) _id(subscriptionId);
    return 'gyms/$gymId';
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() send,
    T Function(Map<String, dynamic>) parse, {
    bool writing = false,
  }) async {
    try {
      final response = object((await send()).data);
      if (response['success'] != true) {
        throw const FormatException('Invalid envelope.');
      }
      return parse(response);
    } on DioException catch (error) {
      throw BillingFailure.fromDio(error, writing: writing);
    } on BillingFailure {
      rethrow;
    } catch (_) {
      throw BillingFailure(
        writing
            ? 'The server result could not be verified. Check membership and payment history before another attempt.'
            : 'The server returned unexpected billing information.',
        uncertain: writing,
      );
    }
  }

  BillingPage<T> _page<T>(
    Map<String, dynamic> response,
    int page,
    T Function(Map<String, dynamic>) parse,
  ) {
    final pagination = Pagination.fromJson(
      object(object(response['meta'])['pagination']),
    );
    final values = items(response['data'], parse);
    if (pagination.page != page ||
        pagination.limit != 20 ||
        values.length > 20) {
      throw const FormatException('Invalid pagination.');
    }
    return BillingPage(values, pagination);
  }

  Map<String, dynamic> _query(int page) =>
      MemberListQuery(page: page).toParameters();
  Membership _subscription(
    Object? data,
    String gymId,
    String memberId, [
    String? id,
  ]) {
    final json = object(data);
    if (json['gymId'] != gymId ||
        json['memberId'] != memberId ||
        id != null && json['id'] != id) {
      throw const FormatException('Subscription scope mismatch.');
    }
    final value = Membership.fromJson(json);
    _id(value.id);
    _id(value.planId);
    if (value.pricePaise > maximumPaymentPaise) {
      throw const FormatException('Invalid price.');
    }
    return value;
  }

  RecordedPayment _payment(
    Map<String, dynamic> json,
    String gymId,
    String memberId,
  ) {
    final payment = RecordedPayment.fromJson(json);
    if (payment.gymId != gymId ||
        payment.memberId != memberId ||
        payment.status != 'succeeded') {
      throw const FormatException('Payment scope/status mismatch.');
    }
    _id(payment.id);
    _id(payment.subscriptionId);
    return payment;
  }

  MembershipPlan _plan(
    Map<String, dynamic> json,
    String gymId, [
    String? planId,
  ]) {
    final plan = MembershipPlan.fromJson(json);
    if (plan.gymId != gymId || planId != null && plan.id != planId) {
      throw const FormatException('Invalid plan scope.');
    }
    _id(plan.id);
    return plan;
  }

  @override
  Future<BillingPage<MembershipPlan>> plans(String gymId, int page) =>
      _plans(gymId, page, activeOnly: true);
  @override
  Future<BillingPage<MembershipPlan>> managePlans(String gymId, int page) =>
      _plans(gymId, page, activeOnly: false);
  Future<BillingPage<MembershipPlan>> _plans(
    String gymId,
    int page, {
    required bool activeOnly,
  }) {
    final path = '${_gym(gymId)}/membership-plans';
    final query = {..._query(page), if (activeOnly) 'status': 'active'};
    return _request(
      () => _client.get(path, queryParameters: query),
      (response) => _page(response, page, (json) {
        final plan = _plan(json, gymId);
        if (activeOnly && plan.status != 'active') {
          throw const FormatException('Invalid plan status.');
        }
        return plan;
      }),
    );
  }

  @override
  Future<MembershipPlan> plan(String gymId, String planId) {
    final path = '${_gym(gymId, planId)}/membership-plans/$planId';
    return _request(
      () => _client.get(path),
      (response) => _plan(object(response['data']), gymId, planId),
    );
  }

  @override
  Future<MembershipPlan> savePlan(
    String gymId,
    PlanDraft draft, {
    String? planId,
  }) async {
    final path =
        '${_gym(gymId, planId)}/membership-plans${planId == null ? '' : '/$planId'}';
    try {
      return await _request(
        () => planId == null
            ? _client.post(path, data: draft.toJson(editing: false))
            : _client.patch(path, data: draft.toJson(editing: true)),
        (response) => _plan(object(response['data']), gymId, planId),
        writing: true,
      );
    } on BillingFailure catch (failure) {
      if (failure.uncertain) {
        throw const BillingFailure(
          'The plan save outcome is uncertain. Recheck Membership Plans before another attempt.',
          uncertain: true,
        );
      }
      rethrow;
    }
  }

  @override
  Future<BillingPage<RecordedPayment>> payments(
    String gymId,
    String memberId,
    int page,
  ) {
    final path = '${_gym(gymId, memberId)}/payments';
    final query = {
      ..._query(page),
      'memberId': memberId,
      'status': 'succeeded',
    };
    return _request(
      () => _client.get(path, queryParameters: query),
      (response) =>
          _page(response, page, (json) => _payment(json, gymId, memberId)),
    );
  }

  @override
  Future<BillingResult> purchase(
    String gymId,
    String memberId,
    PurchaseDraft draft,
  ) {
    final path = '${_gym(gymId, memberId)}/member-memberships';
    _id(draft.planId);
    return _request(() => _client.post(path, data: draft.toJson(memberId)), (
      response,
    ) {
      final data = object(response['data']);
      final subscription = _subscription(data['subscription'], gymId, memberId);
      if (subscription.planId != draft.planId) {
        throw const FormatException('Plan mismatch.');
      }
      final payment = optionalObject(
        data['payment'],
        (json) => _payment(json, gymId, memberId),
      );
      if ((payment != null) != (draft.payment != null) ||
          payment != null &&
              (payment.subscriptionId != subscription.id ||
                  payment.amountPaise != draft.payment!.amountPaise ||
                  payment.method != draft.payment!.method)) {
        throw const FormatException('Purchase payment mismatch.');
      }
      return BillingResult(subscription, payment);
    }, writing: true);
  }

  @override
  Future<BillingResult> cancel(
    String gymId,
    String memberId,
    String subscriptionId,
    String reason,
  ) {
    final path =
        '${_gym(gymId, memberId, subscriptionId)}/members/$memberId/memberships/$subscriptionId/cancel';
    final trimmed = reason.trim();
    if (trimmed.length > 500) {
      throw const BillingFailure('Use at most 500 characters for the reason.');
    }
    return _request(
      () => _client.post(
        path,
        data: {if (trimmed.isNotEmpty) 'cancellationReason': trimmed},
      ),
      (response) {
        final subscription = _subscription(
          response['data'],
          gymId,
          memberId,
          subscriptionId,
        );
        if (subscription.status != 'cancelled') {
          throw const FormatException('Cancellation not confirmed.');
        }
        return BillingResult(subscription);
      },
      writing: true,
    );
  }

  @override
  Future<BillingResult> renew(
    String gymId,
    String memberId,
    String subscriptionId,
  ) async {
    final path =
        '${_gym(gymId, memberId, subscriptionId)}/subscriptions/$subscriptionId/renew';
    // Renewal's URL does not contain memberId. Verify ownership through M23 first.
    await _members.membership(gymId, memberId, subscriptionId);
    return _request(() => _client.post(path, data: <String, dynamic>{}), (
      response,
    ) {
      final subscription = _subscription(response['data'], gymId, memberId);
      if (subscription.previousId != subscriptionId) {
        throw const FormatException('Predecessor mismatch.');
      }
      return BillingResult(subscription);
    }, writing: true);
  }
}
