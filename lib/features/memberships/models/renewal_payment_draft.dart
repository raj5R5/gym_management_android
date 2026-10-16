import 'billing_models.dart';

enum RenewalPaymentChoice { full, partial, later }

class RenewalPaymentDraft {
  const RenewalPaymentDraft({
    this.choice = RenewalPaymentChoice.full,
    this.amount = '',
    this.method = PaymentMethod.cash,
    this.reference = '',
  });
  final RenewalPaymentChoice choice;
  final String amount, reference;
  final PaymentMethod method;
  int amountPaise(int price) {
    if (price == 0 || choice == RenewalPaymentChoice.later) return 0;
    final received = choice == RenewalPaymentChoice.full
        ? price
        : parsePaymentRupees(amount);
    if (received > price) {
      throw const FormatException(
        'Payment cannot exceed the selected plan price.',
      );
    }
    return received;
  }

  String? validation(int price) {
    try {
      if (amountPaise(price) > 0) {
        return paymentReferenceError(method, reference);
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  ManualPayment? payment(int price, DateTime paidAt) {
    final received = amountPaise(price);
    if (received == 0) return null;
    final error = validation(price);
    if (error != null) throw FormatException(error);
    return ManualPayment(
      amountPaise: received,
      method: method,
      paidAt: paidAt,
      reference: reference,
    );
  }
}
