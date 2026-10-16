import 'dart:convert';

import '../../admin_dashboard/models/dashboard_models.dart';
import '../../members/models/member_models.dart';
import '../data/pending_payment_store.dart' show paymentReceiptJson;
import 'billing_models.dart';
import 'renewal_preview.dart';

/// One frozen logical renewal. The predecessor lives in the URL/storage scope.
class RenewalOperationRequest {
  RenewalOperationRequest.fromPreview(
    RenewalPreview preview,
    this.key,
    ManualPayment? payment,
  ) : frozenJson = jsonEncode({
        'planId': preview.planId,
        'expectedTerms': preview.terms,
        if (payment != null)
          'payment': {
            'amountPaise': payment.amountPaise,
            'method': payment.method.wireValue,
            'paidAt': DateTime.fromMillisecondsSinceEpoch(
              payment.paidAt.millisecondsSinceEpoch,
              isUtc: true,
            ).toIso8601String(),
            if (payment.reference.isNotEmpty) 'reference': payment.reference,
          },
      }) {
    validate();
  }
  RenewalOperationRequest.frozen(this.frozenJson, this.key) {
    validate();
  }
  final String frozenJson, key;
  // Return a new map so no caller can modify the persisted request.
  Map<String, dynamic> get body => object(jsonDecode(frozenJson));
  int get pricePaise => integer(object(body['expectedTerms']), 'pricePaise');
  int get receivedPaise => body['payment'] == null
      ? 0
      : integer(object(body['payment']), 'amountPaise');
  int get balancePaise => pricePaise - receivedPaise;
  void validate() {
    final json = body;
    if (!RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(key) ||
        !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(text(json, 'planId')) ||
        !json.keys.toSet().containsAll({'planId', 'expectedTerms'}) ||
        json.keys.toSet().difference({
          'planId',
          'expectedTerms',
          'payment',
        }).isNotEmpty) {
      throw const FormatException('Invalid saved renewal request.');
    }
    final terms = object(json['expectedTerms']);
    if (terms.keys.toSet().difference({
          'planName',
          'durationDays',
          'pricePaise',
          'startDate',
          'endDate',
        }).isNotEmpty ||
        text(terms, 'planName').trim().isEmpty ||
        integer(terms, 'durationDays') < 1 ||
        integer(terms, 'durationDays') > 3650 ||
        pricePaise > maximumPaymentPaise ||
        balancePaise < 0 ||
        CalendarDate.parse(
              text(terms, 'endDate'),
            ).compareTo(CalendarDate.parse(text(terms, 'startDate'))) <=
            0) {
      throw const FormatException('Invalid saved renewal terms.');
    }
    if (json['payment'] != null) {
      final payment = object(json['payment']);
      if (!payment.keys.toSet().containsAll({
            'amountPaise',
            'method',
            'paidAt',
          }) ||
          payment.keys.toSet().difference({
            'amountPaise',
            'method',
            'paidAt',
            'reference',
          }).isNotEmpty ||
          receivedPaise < 1) {
        throw const FormatException('Invalid saved renewal payment.');
      }
      final method = PaymentMethod.values.firstWhere(
        (m) => m.wireValue == text(payment, 'method'),
      );
      final timestamp = text(payment, 'paidAt');
      if (!RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
          ).hasMatch(timestamp) ||
          int.parse(timestamp.substring(11, 13)) > 23 ||
          int.parse(timestamp.substring(14, 16)) > 59 ||
          int.parse(timestamp.substring(17, 19)) > 59) {
        throw const FormatException('Invalid saved renewal timestamp.');
      }
      CalendarDate.parse(timestamp.substring(0, 10));
      final paidAt = DateTime.parse(timestamp);
      if (!paidAt.isUtc ||
          paidAt.isBefore(DateTime.utc(1970)) ||
          paymentReferenceError(
                method,
                optionalText(payment, 'reference') ?? '',
              ) !=
              null) {
        throw const FormatException('Invalid saved renewal payment.');
      }
    }
  }

  void validateResult(
    RenewalResult result, {
    required String gymId,
    required String memberId,
    required String predecessorId,
  }) {
    final subscription = object(result.toJson()['subscription']);
    final terms = object(body['expectedTerms']);
    final requestPayment = body['payment'] == null
        ? null
        : object(body['payment']);
    if (subscription['gymId'] != gymId ||
        subscription['memberId'] != memberId ||
        result.subscription.previousId != predecessorId ||
        result.subscription.planId != body['planId'] ||
        result.subscription.planName != terms['planName'] ||
        result.subscription.durationDays != terms['durationDays'] ||
        result.subscription.pricePaise != pricePaise ||
        result.subscription.startDate.toString() != terms['startDate'] ||
        result.subscription.endDate.toString() != terms['endDate'] ||
        result.receivedPaise != receivedPaise ||
        result.balancePaise != balancePaise ||
        (requestPayment != null) != (result.payment != null)) {
      throw const FormatException('Renewal confirmation mismatch.');
    }
    if (result.payment case final payment?) {
      if (payment.gymId != gymId ||
          payment.memberId != memberId ||
          payment.subscriptionId != result.subscription.id ||
          payment.status != 'succeeded' ||
          payment.method.wireValue != requestPayment!['method'] ||
          payment.reference != requestPayment['reference'] ||
          payment.paidAt.millisecondsSinceEpoch !=
              DateTime.parse(
                requestPayment['paidAt'] as String,
              ).millisecondsSinceEpoch) {
        throw const FormatException('Renewal receipt mismatch.');
      }
    }
  }
}

class RenewalResult extends BillingResult {
  RenewalResult.fromJson(Map<String, dynamic> json)
    : _json = jsonEncode(json),
      receivedPaise = integer(object(json['billing']), 'amountReceivedPaise'),
      balancePaise = integer(
        object(json['billing']),
        'outstandingBalancePaise',
      ),
      super(
        Membership.fromJson(object(json['subscription'])),
        optionalObject(json['payment'], RecordedPayment.fromJson),
      ) {
    if (!['active', 'expired'].contains(subscription.status) ||
        integer(object(json['billing']), 'planPricePaise') !=
            subscription.pricePaise ||
        receivedPaise != (payment?.amountPaise ?? 0) ||
        receivedPaise + balancePaise != subscription.pricePaise ||
        !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(subscription.id) ||
        payment != null &&
            !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(payment!.id)) {
      throw const FormatException('Invalid renewal billing confirmation.');
    }
  }
  final int receivedPaise, balancePaise;
  final String _json;
  Map<String, dynamic> toJson() {
    final sub = object(object(jsonDecode(_json))['subscription']);
    const fields = [
      'id',
      'gymId',
      'memberId',
      'membershipPlanId',
      'previousSubscriptionId',
      'planNameSnapshot',
      'pricePaiseSnapshot',
      'durationDaysSnapshot',
      'startDate',
      'endDate',
      'status',
      'isCurrentlyActive',
    ];
    return {
      'subscription': {for (final field in fields) field: sub[field]},
      'payment': payment == null ? null : paymentReceiptJson(payment!),
      'billing': {
        'planPricePaise': subscription.pricePaise,
        'amountReceivedPaise': receivedPaise,
        'outstandingBalancePaise': balancePaise,
      },
    };
  }
}
