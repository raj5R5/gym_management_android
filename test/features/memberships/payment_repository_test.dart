import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/memberships/data/payment_repository.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'billing_fakes.dart';

void main() {
  late Dio dio;
  late DioPaymentRepository repository;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'));
    repository = DioPaymentRepository(dio);
  });
  tearDown(() => dio.close(force: true));
  PaymentCollection collection() => PaymentCollection(
    memberId: memberId,
    subscriptionId: subscriptionId,
    key: 'test-payment-key',
    payment: ManualPayment(
      amountPaise: 50000,
      method: PaymentMethod.cash,
      paidAt: DateTime.parse('2026-01-01T10:00:00.123456Z'),
    ),
  );
  Map<String, dynamic> revenue() => {
    'success': true,
    'data': [
      paymentJson()
        ..['paidAt'] = '2026-03-01T12:00:00Z'
        ..['member'] = profileJson(),
    ],
    'meta': {
      'period': dashboardJson()['period'],
      'summary': {'successfulAmountPaise': 303, 'successfulPaymentCount': 1},
      'pagination': {'page': 1, 'limit': 20, 'total': 1},
    },
  };
  test(
    'revenue uses existing GET with exact inclusive dates and scoped member DTO',
    () async {
      dio.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/payments');
        expect(request.queryParameters, {
          'page': '1',
          'limit': '20',
          'from': '2026-03-01',
          'to': '2026-03-01',
          'status': 'succeeded',
          'includeMember': 'true',
        });
        return jsonResponse(revenue());
      });
      final result = await repository.revenue(
        gymA,
        DashboardQuery.range(
          CalendarDate(2026, 3, 1),
          CalendarDate(2026, 3, 1),
        ),
        1,
      );
      expect(result.amountPaise, 303);
      expect(result.count, 1);
      expect(result.transactions.single.member.name, 'Alex River');
    },
  );
  test(
    'POST carries one frozen integer-paise body and idempotency key across retries',
    () async {
      final saved = collection();
      final adapter = CallbackAdapter((request) {
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], 'test-payment-key');
        expect(request.data, saved.body);
        final body = paymentJson()
          ..addAll({'amountPaise': 50000, 'paidAt': saved.body['paidAt']});
        return jsonResponse(success(body), status: 201);
      });
      dio.httpClientAdapter = adapter;
      await repository.record(gymA, saved);
      await repository.record(gymA, saved);
      expect(adapter.requests, hasLength(2));
      expect(saved.body['paidAt'], '2026-01-01T10:00:00.123Z');
      expect(() => saved.body['amountPaise'] = 1, throwsUnsupportedError);
    },
  );
  for (final scenario in [
    (status: 409, code: 'PAYMENT_OVERPAYMENT', uncertain: false),
    (status: 409, code: 'IDEMPOTENCY_KEY_CONFLICT', uncertain: true),
    (status: 503, code: 'PAYMENT_STORAGE_UNAVAILABLE', uncertain: true),
  ]) {
    test('${scenario.code} has conservative collection behavior', () async {
      dio.httpClientAdapter = CallbackAdapter(
        (_) =>
            jsonResponse(failureBody(scenario.code), status: scenario.status),
      );
      await expectLater(
        repository.record(gymA, collection()),
        throwsA(
          isA<BillingFailure>().having(
            (error) => error.uncertain,
            'uncertain',
            scenario.uncertain,
          ),
        ),
      );
    });
  }
  test(
    'transport timeout is uncertain and does not manufacture a payment',
    () async {
      dio.httpClientAdapter = CallbackAdapter(
        (request) => throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      await expectLater(
        repository.record(gymA, collection()),
        throwsA(
          isA<BillingFailure>().having(
            (error) => error.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
    },
  );
  for (final wrong in ['gym', 'date', 'status', 'member']) {
    test('revenue rejects $wrong scope mismatch', () async {
      final body = revenue();
      final row = (body['data'] as List).single as Map;
      if (wrong == 'gym') row['gymId'] = gymB;
      if (wrong == 'date') row['paidAt'] = '2026-03-02T12:00:00Z';
      if (wrong == 'status') row['status'] = 'failed';
      if (wrong == 'member') (row['member'] as Map)['id'] = gymB;
      dio.httpClientAdapter = CallbackAdapter((_) => jsonResponse(body));
      await expectLater(
        repository.revenue(
          gymA,
          DashboardQuery.range(
            CalendarDate(2026, 3, 1),
            CalendarDate(2026, 3, 1),
          ),
          1,
        ),
        throwsA(isA<BillingFailure>()),
      );
    });
  }
  for (final wrong in ['id', 'gymId', 'amountPaise', 'paidAt']) {
    test(
      'unverifiable successful $wrong is uncertain and never confirms',
      () async {
        final saved = collection();
        final body = paymentJson()
          ..addAll({'amountPaise': 50000, 'paidAt': saved.body['paidAt']});
        body[wrong] = switch (wrong) {
          'id' => 'bad',
          'gymId' => gymB,
          'amountPaise' => 1,
          _ => '2026-01-01T11:00:00Z',
        };
        dio.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse(success(body), status: 201),
        );
        await expectLater(
          repository.record(gymA, saved),
          throwsA(
            isA<BillingFailure>().having(
              (error) => error.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
      },
    );
  }
  for (final outcome in [
    (status: 408, code: 'TIMEOUT'),
    (status: 409, code: 'UNKNOWN_ERROR'),
    (status: 409, code: 'VALIDATION_ERROR'),
    (status: 400, code: 'PAYMENT_OVERPAYMENT'),
  ]) {
    test(
      'unknown or mismatched ${outcome.status}/${outcome.code} keeps exact recovery blocked',
      () async {
        dio.httpClientAdapter = CallbackAdapter(
          (_) =>
              jsonResponse(failureBody(outcome.code), status: outcome.status),
        );
        await expectLater(
          repository.record(gymA, collection()),
          throwsA(
            isA<BillingFailure>().having(
              (error) => error.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
      },
    );
  }
}
