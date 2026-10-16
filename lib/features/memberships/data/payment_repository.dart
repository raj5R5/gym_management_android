import 'dart:convert';
import 'package:dio/dio.dart';

import '../../admin_dashboard/models/dashboard_models.dart';
import '../../auth/data/auth_failure.dart';
import '../../members/models/member_models.dart';
import '../models/billing_models.dart';
import 'billing_failure.dart';

class RevenueTransaction {
  RevenueTransaction(this.payment, this.member);
  final RecordedPayment payment;
  final MemberProfile member;
}

class RevenuePage {
  RevenuePage(
    this.transactions,
    this.pagination,
    this.period,
    this.amountPaise,
    this.count,
  );
  final List<RevenueTransaction> transactions;
  final Pagination pagination;
  final DashboardPeriod period;
  final int amountPaise, count;
}

/// Immutable logical collection. Retries use this same key, timestamp and body.
class PaymentCollection {
  PaymentCollection({
    required this.memberId,
    required this.subscriptionId,
    required this.key,
    required ManualPayment payment,
  }) : body = Map.unmodifiable({
         'memberId': memberId,
         'subscriptionId': subscriptionId,
         'amountPaise': payment.amountPaise,
         'paymentMethod': payment.method.wireValue,
         'paidAt': DateTime.fromMillisecondsSinceEpoch(
           payment.paidAt.millisecondsSinceEpoch,
           isUtc: true,
         ).toIso8601String(),
         if (payment.reference.isNotEmpty)
           'transactionReference': payment.reference,
       }),
       _originalJson = null;
  PaymentCollection.fromFrozenJson(String frozenJson, this.key)
    : body = Map.unmodifiable(object(jsonDecode(frozenJson))),
      _originalJson = frozenJson {
    final keys = body.keys.toSet();
    const required = {
      'memberId',
      'subscriptionId',
      'amountPaise',
      'paymentMethod',
      'paidAt',
    };
    if (!keys.containsAll(required) ||
        keys.difference({...required, 'transactionReference'}).isNotEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(key)) {
      throw const FormatException('Invalid saved payment request.');
    }
    for (final field in ['memberId', 'subscriptionId']) {
      if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(text(body, field))) {
        throw const FormatException('Invalid saved payment identity.');
      }
    }
    final amount = integer(body, 'amountPaise');
    final method = PaymentMethod.values.firstWhere(
      (method) => method.wireValue == text(body, 'paymentMethod'),
    );
    final timestamp = text(body, 'paidAt');
    if (!RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
        ).hasMatch(timestamp) ||
        int.parse(timestamp.substring(11, 13)) > 23 ||
        int.parse(timestamp.substring(14, 16)) > 59 ||
        int.parse(timestamp.substring(17, 19)) > 59) {
      throw const FormatException('Invalid saved payment timestamp.');
    }
    CalendarDate.parse(timestamp.substring(0, 10));
    if (body.containsKey('transactionReference') &&
        (body['transactionReference'] is! String ||
            (body['transactionReference'] as String).trim().isEmpty)) {
      throw const FormatException('Invalid saved reference.');
    }
    final paidAt = DateTime.parse(timestamp);
    if (amount < 1 ||
        amount > maximumPaymentPaise ||
        !paidAt.isUtc ||
        paidAt.isBefore(DateTime.utc(1970)) ||
        paymentReferenceError(
              method,
              optionalText(body, 'transactionReference') ?? '',
            ) !=
            null) {
      throw const FormatException('Invalid saved payment.');
    }
    memberId = text(body, 'memberId');
    subscriptionId = text(body, 'subscriptionId');
  }
  late final String memberId, subscriptionId;
  final String key;
  final Map<String, dynamic> body;
  final String? _originalJson;
  String get frozenJson => _originalJson ?? jsonEncode(body);

  void validateResult(RecordedPayment payment, String gymId, {String? userId}) {
    if (payment.gymId != gymId ||
        !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(payment.id) ||
        payment.memberId != memberId ||
        payment.subscriptionId != subscriptionId ||
        payment.status != 'succeeded' ||
        payment.amountPaise != body['amountPaise'] ||
        payment.method.wireValue != body['paymentMethod'] ||
        payment.reference != body['transactionReference'] ||
        payment.paidAt.millisecondsSinceEpoch !=
            DateTime.parse(body['paidAt'] as String).millisecondsSinceEpoch ||
        (userId != null &&
            payment.recordedByUserId != null &&
            payment.recordedByUserId != userId)) {
      throw const FormatException('Payment confirmation mismatch.');
    }
  }
}

abstract interface class PaymentRepository {
  Future<RevenuePage> revenue(String gymId, DashboardQuery range, int page);
  Future<RecordedPayment> record(
    String gymId,
    PaymentCollection collection, {
    CancelToken? cancelToken,
  });
}

class DioPaymentRepository implements PaymentRepository {
  DioPaymentRepository(this._client);
  final Dio _client;
  void _id(String value) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value)) {
      throw const BillingFailure('Invalid payment context.');
    }
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() send,
    T Function(Map<String, dynamic>) parse, {
    bool writing = false,
  }) async {
    try {
      final body = object((await send()).data);
      if (body['success'] != true) {
        throw const FormatException('Invalid payment envelope.');
      }
      return parse(body);
    } on DioException catch (error) {
      final code = objectCode(error);
      if (code == 'IDEMPOTENCY_KEY_CONFLICT') {
        throw const BillingFailure(
          'This payment key conflicts with a saved transaction. Check payment history; do not record it again.',
          uncertain: true,
          code: 'IDEMPOTENCY_KEY_CONFLICT',
        );
      }
      if (writing &&
          (error.error is AuthFailure ||
              !paymentRejections.containsKey(code) ||
              paymentRejections[code] != error.response?.statusCode)) {
        throw const BillingFailure(
          'The payment outcome is uncertain. Retry the saved payment or check history before collecting again.',
          uncertain: true,
        );
      }
      final failure = BillingFailure.fromDio(error, writing: writing);
      throw BillingFailure(
        failure.message,
        uncertain: failure.uncertain,
        code: writing ? code : failure.code,
        httpStatus: error.response?.statusCode,
      );
    } on BillingFailure {
      rethrow;
    } catch (_) {
      throw BillingFailure(
        writing
            ? 'The payment outcome could not be verified. Retry the saved payment or check history.'
            : 'Payment history could not be verified.',
        uncertain: writing,
      );
    }
  }

  String? objectCode(DioException error) {
    final body = error.response?.data;
    final code = body is Map && body['error'] is Map
        ? (body['error'] as Map)['code']
        : null;
    return code is String ? code : null;
  }

  @override
  Future<RevenuePage> revenue(String gymId, DashboardQuery range, int page) {
    _id(gymId);
    if (range.filter != DashboardDateFilter.customRange) {
      throw const BillingFailure('Choose an exact revenue range.');
    }
    final query = {
      ...MemberListQuery(page: page).toParameters(),
      ...range.toParameters(),
      'status': 'succeeded',
      'includeMember': 'true',
    };
    return _request(
      () => _client.get('gyms/$gymId/payments', queryParameters: query),
      (body) {
        final meta = object(body['meta']);
        final period = DashboardPeriod.fromJson(object(meta['period']));
        final pagination = Pagination.fromJson(object(meta['pagination']));
        if (period.branchId != null ||
            period.from.toString() != range.from.toString() ||
            period.to.toString() != range.to.toString() ||
            pagination.page != page ||
            pagination.limit != 20) {
          throw const FormatException('Revenue scope mismatch.');
        }
        final transactions = items(body['data'], (json) {
          final payment = RecordedPayment.fromJson(json);
          final member = MemberProfile.fromJson(object(json['member']));
          if (payment.gymId != gymId ||
              !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(payment.id) ||
              !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(member.id) ||
              payment.memberId != member.id ||
              member.gymId != gymId ||
              payment.status != 'succeeded' ||
              payment.paidAt.isBefore(period.startUtc) ||
              !payment.paidAt.isBefore(period.endUtc)) {
            throw const FormatException('Payment scope mismatch.');
          }
          return RevenueTransaction(payment, member);
        });
        final summary = object(meta['summary']);
        final count = integer(summary, 'successfulPaymentCount');
        if (transactions.length > 20 || count != pagination.total) {
          throw const FormatException('Revenue count mismatch.');
        }
        return RevenuePage(
          transactions,
          pagination,
          period,
          integer(summary, 'successfulAmountPaise'),
          count,
        );
      },
    );
  }

  @override
  Future<RecordedPayment> record(
    String gymId,
    PaymentCollection collection, {
    CancelToken? cancelToken,
  }) {
    _id(gymId);
    _id(collection.memberId);
    _id(collection.subscriptionId);
    if (!RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(collection.key)) {
      throw const BillingFailure('Invalid payment key.');
    }
    return _request(
      () => _client.post(
        'gyms/$gymId/payments',
        data: collection.body,
        cancelToken: cancelToken,
        options: Options(headers: {'Idempotency-Key': collection.key}),
      ),
      (body) {
        final payment = RecordedPayment.fromJson(object(body['data']));
        collection.validateResult(payment, gymId);
        return payment;
      },
      writing: true,
    );
  }
}
