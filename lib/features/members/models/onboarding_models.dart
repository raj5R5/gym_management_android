import 'dart:convert';

import '../../admin_dashboard/models/dashboard_models.dart';
import '../../memberships/models/billing_models.dart';
import 'member_draft.dart';
import 'member_models.dart';

String onboardingId(Object? value) {
  if (value is! String || !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value)) {
    throw const FormatException('Invalid onboarding identity.');
  }
  return value;
}

void validateOnboardingKey(String key) {
  if (!RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(key)) {
    throw const FormatException('Invalid onboarding operation key.');
  }
}

void _shape(
  Map<String, dynamic> json,
  Set<String> allowed,
  Set<String> required,
) {
  if (!allowed.containsAll(json.keys) ||
      !json.keys.toSet().containsAll(required)) {
    throw const FormatException('Invalid onboarding fields.');
  }
}

int _money(Map<String, dynamic> json, String key) {
  final value = integer(json, key);
  if (value > maximumPaymentPaise) {
    throw const FormatException('Invalid onboarding amount.');
  }
  return value;
}

DateTime _timestamp(String value) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
  ).hasMatch(value)) {
    throw const FormatException('Invalid onboarding timestamp.');
  }
  CalendarDate.parse(value.substring(0, 10));
  if (int.parse(value.substring(11, 13)) > 23 ||
      int.parse(value.substring(14, 16)) > 59 ||
      int.parse(value.substring(17, 19)) > 59) {
    throw const FormatException('Invalid onboarding timestamp.');
  }
  final parsed = DateTime.parse(value);
  if (parsed.isBefore(DateTime.utc(1970))) {
    throw const FormatException('Invalid onboarding timestamp.');
  }
  return parsed;
}

PaymentMethod _method(String value) => PaymentMethod.values.firstWhere(
  (method) => method.wireValue == value,
  orElse: () =>
      throw const FormatException('Invalid onboarding payment method.'),
);

/// Different from legacy ManualPayment: no enabled flag, and zero is supported.
class OnboardingPayment {
  OnboardingPayment({
    required this.method,
    required this.amountPaise,
    required DateTime paidAt,
    String reference = '',
  }) : paidAt = DateTime.fromMillisecondsSinceEpoch(
         paidAt.millisecondsSinceEpoch,
         isUtc: true,
       ),
       reference = reference.trim() {
    if (amountPaise < 0 ||
        amountPaise > maximumPaymentPaise ||
        paidAt.isBefore(DateTime.utc(1970)) ||
        paidAt.isAfter(DateTime.now()) ||
        (this.reference.isNotEmpty || amountPaise > 0) &&
            paymentReferenceError(method, this.reference) != null) {
      throw const FormatException('Invalid initial payment.');
    }
  }
  final PaymentMethod method;
  final int amountPaise;
  final DateTime paidAt;
  final String reference;
  Map<String, dynamic> toJson() => {
    'method': method.wireValue,
    'amountPaise': amountPaise,
    'paidAt': paidAt.toUtc().toIso8601String(),
    if (reference.isNotEmpty) 'reference': reference,
  };
}

class OnboardingMembership {
  OnboardingMembership({required this.planId, this.startDate, this.payment}) {
    onboardingId(planId);
    if (startDate != null && startDate!.value.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Future membership starts are unsupported.');
    }
  }
  final String planId;
  final CalendarDate? startDate;
  final OnboardingPayment? payment;
  Map<String, dynamic> toJson() => {
    'planId': planId,
    if (startDate != null) 'startDate': startDate.toString(),
    if (payment != null) 'payment': payment!.toJson(),
  };
}

/// Immutable serialized snapshot. Every read produces a detached JSON object;
/// restoring never normalizes fields or recalculates dates, amounts or timestamps.
class OnboardingRequest {
  factory OnboardingRequest({
    required MemberDraft member,
    OnboardingMembership? membership,
    String? branchId,
  }) => OnboardingRequest.fromFrozenJson(
    jsonEncode({
      'member': {
        ...member.toJson(editing: false),
        if (branchId != null) 'branchId': onboardingId(branchId),
      },
      if (membership != null) 'membership': membership.toJson(),
    }),
  );

  OnboardingRequest.fromFrozenJson(this.frozenJson) {
    final body = toJson();
    _shape(body, {'member', 'membership'}, {'member'});
    final member = object(body['member']);
    _shape(
      member,
      {
        'memberCode',
        'firstName',
        'lastName',
        'phone',
        'branchId',
        'dateOfBirth',
        'gender',
        'address',
        'emergencyContact',
      },
      {'memberCode', 'firstName', 'lastName', 'phone'},
    );
    if (validateMemberCode(text(member, 'memberCode')) != null ||
        validateName(text(member, 'firstName')) != null ||
        validateName(text(member, 'lastName')) != null ||
        validatePhone(text(member, 'phone')) != null) {
      throw const FormatException('Invalid onboarding member.');
    }
    if (member.containsKey('branchId')) onboardingId(member['branchId']);
    if (member['dateOfBirth'] != null) {
      CalendarDate.parse(text(member, 'dateOfBirth'));
    }
    if (member['gender'] != null && !memberGenders.contains(member['gender'])) {
      throw const FormatException('Invalid onboarding gender.');
    }
    if (member['address'] != null) {
      final address = object(member['address']);
      _shape(
        address,
        {'line1', 'line2', 'city', 'state', 'postalCode', 'countryCode'},
        {'line1', 'city', 'countryCode'},
      );
      _boundedText(address, 'line1', 200);
      _boundedText(address, 'city', 100);
      for (final field in {
        'line2': 200,
        'state': 100,
        'postalCode': 20,
      }.entries) {
        if (address.containsKey(field.key)) {
          _boundedText(address, field.key, field.value);
        }
      }
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(text(address, 'countryCode'))) {
        throw const FormatException('Invalid onboarding address.');
      }
    }
    if (member['emergencyContact'] != null) {
      final contact = object(member['emergencyContact']);
      _shape(contact, {'name', 'phone', 'relationship'}, {'name', 'phone'});
      _boundedText(contact, 'name', 120);
      if (validatePhone(text(contact, 'phone')) != null) {
        throw const FormatException('Invalid emergency contact.');
      }
      if (contact.containsKey('relationship')) {
        _boundedText(contact, 'relationship', 80);
      }
    }
    if (body.containsKey('membership')) {
      final membership = object(body['membership']);
      _shape(membership, {'planId', 'startDate', 'payment'}, {'planId'});
      onboardingId(membership['planId']);
      if (membership.containsKey('startDate')) {
        CalendarDate.parse(text(membership, 'startDate'));
      }
      if (membership.containsKey('payment')) {
        final payment = object(membership['payment']);
        _shape(
          payment,
          {'method', 'amountPaise', 'paidAt', 'reference'},
          {'method', 'amountPaise', 'paidAt'},
        );
        final method = _method(text(payment, 'method'));
        final amount = _money(payment, 'amountPaise');
        _timestamp(text(payment, 'paidAt'));
        final reference = payment.containsKey('reference')
            ? text(payment, 'reference')
            : '';
        if (payment.containsKey('reference') && reference.trim().isEmpty ||
            (reference.isNotEmpty || amount > 0) &&
                paymentReferenceError(method, reference) != null) {
          throw const FormatException('Invalid initial payment reference.');
        }
      }
    }
  }
  final String frozenJson;
  Map<String, dynamic> toJson() => object(jsonDecode(frozenJson));
}

void _boundedText(Map<String, dynamic> json, String key, int maximum) {
  final value = text(json, key).trim();
  if (value.isEmpty || value.length > maximum) {
    throw const FormatException('Invalid onboarding text.');
  }
}

class OnboardedMember {
  OnboardedMember.fromJson(Map<String, dynamic> json)
    : id = onboardingId(json['id']),
      gymId = onboardingId(json['gymId']),
      branchId = json['branchId'] == null
          ? null
          : onboardingId(json['branchId']),
      memberCode = text(json, 'memberCode'),
      firstName = text(json, 'firstName'),
      lastName = text(json, 'lastName'),
      status = text(json, 'status') {
    _shape(
      json,
      {
        'id',
        'gymId',
        'branchId',
        'memberCode',
        'firstName',
        'lastName',
        'status',
      },
      {'id', 'gymId', 'memberCode', 'firstName', 'lastName', 'status'},
    );
    if (status != 'active') {
      throw const FormatException('Invalid onboarding member status.');
    }
  }
  final String id, gymId, memberCode, firstName, lastName, status;
  final String? branchId;
}

class OnboardedSubscription {
  OnboardedSubscription.fromJson(Map<String, dynamic> json)
    : id = onboardingId(json['id']),
      planId = onboardingId(json['membershipPlanId']),
      planName = text(json, 'planNameSnapshot'),
      durationDays = integer(json, 'durationDaysSnapshot'),
      pricePaise = _money(json, 'pricePaiseSnapshot'),
      startDate = CalendarDate.parse(text(json, 'startDate')),
      endDate = CalendarDate.parse(text(json, 'endDate')),
      status = text(json, 'status'),
      currentlyActive = boolean(json, 'isCurrentlyActive') {
    _shape(
      json,
      {
        'id',
        'membershipPlanId',
        'planNameSnapshot',
        'durationDaysSnapshot',
        'pricePaiseSnapshot',
        'startDate',
        'endDate',
        'status',
        'isCurrentlyActive',
      },
      {
        'id',
        'membershipPlanId',
        'planNameSnapshot',
        'durationDaysSnapshot',
        'pricePaiseSnapshot',
        'startDate',
        'endDate',
        'status',
        'isCurrentlyActive',
      },
    );
    if (durationDays < 1 ||
        durationDays > 3650 ||
        startDate.compareTo(endDate) >= 0 ||
        !['active', 'expired'].contains(status)) {
      throw const FormatException('Invalid onboarding subscription.');
    }
  }
  final String id, planId, planName, status;
  final int durationDays, pricePaise;
  final CalendarDate startDate, endDate;
  final bool currentlyActive;
}

class OnboardedPayment {
  OnboardedPayment.fromJson(Map<String, dynamic> json)
    : id = onboardingId(json['id']),
      subscriptionId = onboardingId(json['subscriptionId']),
      amountPaise = _money(json, 'amountPaise'),
      method = _method(text(json, 'paymentMethod')),
      paidAt = _timestamp(text(json, 'paidAt')),
      reference = optionalText(json, 'transactionReference') {
    _shape(
      json,
      {
        'id',
        'subscriptionId',
        'amountPaise',
        'paymentMethod',
        'paidAt',
        'transactionReference',
      },
      {'id', 'subscriptionId', 'amountPaise', 'paymentMethod', 'paidAt'},
    );
    if (amountPaise == 0) {
      throw const FormatException('Invalid recorded onboarding payment.');
    }
  }
  final String id, subscriptionId;
  final int amountPaise;
  final PaymentMethod method;
  final DateTime paidAt;
  final String? reference;
}

class OnboardingBillingSummary {
  OnboardingBillingSummary.fromJson(Map<String, dynamic> json)
    : planPricePaise = _money(json, 'planPricePaise'),
      discountPaise = _money(json, 'discountPaise'),
      amountReceivedPaise = _money(json, 'amountReceivedPaise'),
      outstandingBalancePaise = _money(json, 'outstandingBalancePaise') {
    _shape(
      json,
      {
        'planPricePaise',
        'discountPaise',
        'amountReceivedPaise',
        'outstandingBalancePaise',
      },
      {
        'planPricePaise',
        'discountPaise',
        'amountReceivedPaise',
        'outstandingBalancePaise',
      },
    );
    if (discountPaise != 0 ||
        amountReceivedPaise > planPricePaise ||
        outstandingBalancePaise != planPricePaise - amountReceivedPaise) {
      throw const FormatException('Invalid onboarding billing summary.');
    }
  }
  final int planPricePaise,
      discountPaise,
      amountReceivedPaise,
      outstandingBalancePaise;
}

class OnboardingResult {
  OnboardingResult.fromJson(Map<String, dynamic> json)
    : _json = jsonEncode(json),
      operationId = onboardingId(json['operationId']),
      member = OnboardedMember.fromJson(object(json['member'])),
      subscription = optionalObject(
        json['subscription'],
        OnboardedSubscription.fromJson,
      ),
      payment = optionalObject(json['payment'], OnboardedPayment.fromJson),
      billing = OnboardingBillingSummary.fromJson(object(json['billing'])) {
    _shape(
      json,
      {'operationId', 'member', 'subscription', 'payment', 'billing'},
      {'operationId', 'member', 'subscription', 'payment', 'billing'},
    );
    if (!json.containsKey('subscription') ||
        !json.containsKey('payment') ||
        billing.planPricePaise != (subscription?.pricePaise ?? 0) ||
        billing.amountReceivedPaise != (payment?.amountPaise ?? 0) ||
        payment != null && payment!.subscriptionId != subscription?.id) {
      throw const FormatException('Inconsistent onboarding result.');
    }
  }
  final String _json, operationId;
  final OnboardedMember member;
  final OnboardedSubscription? subscription;
  final OnboardedPayment? payment;
  final OnboardingBillingSummary billing;
  Map<String, dynamic> toJson() => object(jsonDecode(_json));

  /// Compare identities and explicitly supplied inputs, never predict server terms.
  void validateFor(String gymId, OnboardingRequest request) {
    final body = request.toJson();
    final input = object(body['member']);
    final membership = body['membership'] == null
        ? null
        : object(body['membership']);
    final initial = membership?['payment'] == null
        ? null
        : object(membership!['payment']);
    if (member.gymId.toLowerCase() != gymId.toLowerCase() ||
        member.memberCode != text(input, 'memberCode').trim().toUpperCase() ||
        member.firstName != text(input, 'firstName').trim() ||
        member.lastName != text(input, 'lastName').trim() ||
        member.branchId?.toLowerCase() !=
            (input['branchId'] as String?)?.toLowerCase() ||
        (membership == null) != (subscription == null) ||
        subscription != null &&
            subscription!.planId.toLowerCase() !=
                text(membership!, 'planId').toLowerCase() ||
        membership?['startDate'] != null &&
            subscription!.startDate.toString() != membership!['startDate'] ||
        (payment != null) != (initial != null && initial['amountPaise'] > 0) ||
        payment != null &&
            (payment!.amountPaise != initial!['amountPaise'] ||
                payment!.method.wireValue != initial['method'] ||
                // MongoDB dates have millisecond precision. Compare at that
                // precision without rewriting older frozen request timestamps.
                payment!.paidAt.millisecondsSinceEpoch !=
                    _timestamp(
                      text(initial, 'paidAt'),
                    ).millisecondsSinceEpoch ||
                payment!.reference !=
                    (initial['reference'] as String?)?.trim())) {
      throw const FormatException('Onboarding response context mismatch.');
    }
  }
}
