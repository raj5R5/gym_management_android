import '../../members/models/member_models.dart';

const maximumPaymentPaise = 1000000000;

enum PaymentMethod {
  cash('Cash', 'cash'),
  upi('UPI', 'upi'),
  bankTransfer('Bank transfer', 'bank_transfer'),
  card('Card', 'card'),
  other('Other', 'other');

  const PaymentMethod(this.label, this.wireValue);
  final String label, wireValue;
  bool get requiresReference =>
      this == upi || this == bankTransfer || this == card;
}

/// Decimal input is converted using integers only. Commas/exponents are rejected.
int parsePaymentRupees(String input, {bool allowZero = false}) {
  final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) {
    throw const FormatException(
      'Enter rupees with at most two decimal places.',
    );
  }
  final paise =
      int.parse(match.group(1)!) * 100 +
      int.parse((match.group(2) ?? '').padRight(2, '0'));
  if (paise < (allowZero ? 0 : 1) || paise > maximumPaymentPaise) {
    throw FormatException(
      allowZero
          ? 'Enter an amount from ₹0.00 to ₹1,00,00,000.00.'
          : 'Enter an amount from ₹0.01 to ₹1,00,00,000.00.',
    );
  }
  return paise;
}

String? paymentReferenceError(PaymentMethod method, String input) {
  final value = input.trim();
  if (value.isEmpty) {
    return method.requiresReference ? 'A payment reference is required.' : null;
  }
  if (value.length < 3 ||
      value.length > 120 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._:/-]*$').hasMatch(value)) {
    return 'Use 3–120 letters, numbers, spaces or . _ : / - for the reference.';
  }
  return null;
}

/// Zero means no initial payment object. Plan terms still come from the server.
int parseInitialPaymentRupees(String input, {required int planPricePaise}) {
  if (input.trim().startsWith('-')) {
    throw const FormatException('The initial payment cannot be negative.');
  }
  final amount = parsePaymentRupees(input, allowZero: true);
  if (amount > planPricePaise) {
    throw const FormatException(
      'Payment cannot exceed the selected plan price.',
    );
  }
  return amount;
}

class MembershipPlan {
  MembershipPlan.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      gymId = text(json, 'gymId'),
      name = text(json, 'name'),
      durationDays = integer(json, 'durationDays'),
      pricePaise = integer(json, 'price'),
      status = text(json, 'status'),
      description = optionalText(json, 'description'),
      activeMemberCount = json['activeMemberCount'] is int
          ? json['activeMemberCount'] as int
          : null {
    if (durationDays < 1 ||
        durationDays > 3650 ||
        pricePaise > maximumPaymentPaise ||
        !['active', 'inactive'].contains(status)) {
      throw const FormatException('Invalid membership plan.');
    }
  }
  final String id, gymId, name, status;
  final int durationDays, pricePaise;
  final String? description;

  /// Members currently on this plan; null from servers that don't report it.
  final int? activeMemberCount;
}

class BillingPage<T> {
  BillingPage(this.items, this.pagination);
  final List<T> items;
  final Pagination pagination;
}

class RecordedPayment {
  RecordedPayment.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      gymId = text(json, 'gymId'),
      memberId = text(json, 'memberId'),
      subscriptionId = text(json, 'subscriptionId'),
      amountPaise = integer(json, 'amountPaise'),
      status = text(json, 'status'),
      method = PaymentMethod.values.firstWhere(
        (value) => value.wireValue == text(json, 'paymentMethod'),
      ),
      paidAt = DateTime.parse(text(json, 'paidAt')),
      reference = optionalText(json, 'transactionReference'),
      recordedByUserId = optionalText(json, 'recordedByUserId'),
      isOpeningBalance = json['isOpeningBalance'] == true {
    if (amountPaise < 1 ||
        amountPaise > maximumPaymentPaise ||
        !['pending', 'succeeded', 'failed', 'cancelled'].contains(status) ||
        !paidAt.isUtc) {
      throw const FormatException('Invalid payment.');
    }
  }
  final String id, gymId, memberId, subscriptionId, status;
  final int amountPaise;
  final PaymentMethod method;
  final DateTime paidAt;
  final String? reference, recordedByUserId;

  /// Paid before the gym started using the app.
  final bool isOpeningBalance;
}

class ManualPayment {
  ManualPayment({
    required this.amountPaise,
    required this.method,
    required this.paidAt,
    String reference = '',
  }) : reference = reference.trim() {
    if (amountPaise < 1 ||
        amountPaise > maximumPaymentPaise ||
        paidAt.isBefore(DateTime.utc(1970)) ||
        paidAt.isAfter(DateTime.now()) ||
        paymentReferenceError(method, reference) != null) {
      throw const FormatException('Invalid payment information.');
    }
  }
  final int amountPaise;
  final PaymentMethod method;
  final DateTime paidAt;
  final String reference;
  Map<String, dynamic> toJson() => {
    'enabled': true,
    'amountPaise': amountPaise,
    'method': method.wireValue,
    'paidAt': paidAt.toUtc().toIso8601String(),
    if (reference.isNotEmpty) 'reference': reference,
  };
}

class PurchaseDraft {
  PurchaseDraft({required this.planId, this.payment});
  final String planId;
  final ManualPayment? payment;
  Map<String, dynamic> toJson(String memberId) => {
    'memberId': memberId,
    'planId': planId,
    if (payment != null) 'payment': payment!.toJson(),
  };
}

class BillingResult {
  BillingResult(this.subscription, [this.payment]);
  final Membership subscription;
  final RecordedPayment? payment;
}

class PlanDraft {
  PlanDraft({
    required String name,
    required this.durationDays,
    required this.pricePaise,
    required this.status,
    String description = '',
  }) : name = name.trim(),
       description = description.trim() {
    if (this.name.isEmpty ||
        this.name.length > 120 ||
        this.description.length > 2000 ||
        durationDays < 1 ||
        durationDays > 3650 ||
        pricePaise < 0 ||
        pricePaise > maximumPaymentPaise ||
        !['active', 'inactive'].contains(status)) {
      throw const FormatException('Check the membership plan fields.');
    }
  }
  final String name, description, status;
  final int durationDays, pricePaise;
  Map<String, dynamic> toJson({required bool editing}) => {
    'name': name,
    'durationDays': durationDays,
    'price': pricePaise,
    'status': status,
    if (description.isNotEmpty || editing)
      'description': description.isEmpty ? null : description,
  };
}
