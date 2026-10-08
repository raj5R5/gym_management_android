import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';

class BillingFailure implements Exception {
  const BillingFailure(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
  factory BillingFailure.fromDio(DioException error, {required bool writing}) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    // No write retry on transport failures, server failures or unreadable success.
    final uncertain =
        writing &&
        (error.response == null && error.error is! AuthFailure ||
            (error.response?.statusCode ?? 0) >= 500);
    if (uncertain) {
      return const BillingFailure(
        'The outcome is uncertain. Check membership and payment history before another attempt.',
        uncertain: true,
      );
    }
    return BillingFailure(switch (code) {
      'SUBSCRIPTION_OVERLAP' =>
        'This period overlaps an existing membership. Check membership history.',
      'SUBSCRIPTION_ALREADY_RENEWED' =>
        'This membership has already been renewed. Refresh history.',
      'SUBSCRIPTION_CANCELLED' || 'PAYMENT_SUBSCRIPTION_CANCELLED' =>
        'This membership is cancelled. Refresh history.',
      'PAYMENT_OVERPAYMENT' =>
        'The payment exceeds the balance allowed by the server.',
      'DUPLICATE_PAYMENT_REFERENCE' =>
        'That payment reference has already been recorded. Check payment history.',
      'DUPLICATE_PLAN_NAME' =>
        'A plan with that name already exists in this gym. Check Membership Plans.',
      'PLAN_NOT_FOUND' => 'That plan is unavailable. Refresh the active plans.',
      'SUBSCRIPTION_NOT_FOUND' || 'MEMBER_NOT_FOUND' =>
        'The member or membership is no longer available in this gym.',
      'VALIDATION_ERROR' =>
        'Check the information entered. The server could not validate it.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'BillingFailure: $message';
}
