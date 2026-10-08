import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/members/data/member_repository.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/data/membership_repository.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import '../members/member_repository_test.dart' show envelope;
import 'billing_fakes.dart';

void main() {
  late Dio client;
  late DioMembershipRepository repository;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioMembershipRepository(client, DioMemberRepository(client));
  });
  tearDown(() => client.close(force: true));
  test(
    'active plan list uses server status/pagination without branch filter',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/membership-plans');
        expect(request.queryParameters, {
          'page': '2',
          'limit': '20',
          'status': 'active',
        });
        return jsonResponse(envelope([planJson()], page: 2, total: 21));
      });
      expect((await repository.plans(gymA, 2)).items.single.pricePaise, 150000);
    },
  );
  test(
    'payment history reads only succeeded records for scoped member',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/payments');
        expect(request.queryParameters, {
          'page': '1',
          'limit': '20',
          'memberId': memberId,
          'status': 'succeeded',
        });
        return jsonResponse(envelope([paymentJson()]));
      });
      expect(
        (await repository.payments(gymA, memberId, 1)).items.single.amountPaise,
        303,
      );
    },
  );
  test('purchase POST without payment sends minimal M22 body', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/gyms/$gymA/member-memberships');
      expect(request.data, {'memberId': memberId, 'planId': planId});
      return jsonResponse(
        envelope({'subscription': fullSubscription(), 'payment': null}),
        status: 201,
      );
    });
    expect(
      (await repository.purchase(
        gymA,
        memberId,
        PurchaseDraft(planId: planId),
      )).payment,
      isNull,
    );
  });
  for (final method in PaymentMethod.values) {
    test(
      'atomic purchase with ${method.wireValue} uses exact payment fields',
      () async {
        final payment = ManualPayment(
          amountPaise: 303,
          method: method,
          paidAt: DateTime.utc(2020),
          reference: method.requiresReference ? 'REF-001' : '',
        );
        final draft = PurchaseDraft(planId: planId, payment: payment);
        client.httpClientAdapter = CallbackAdapter((request) {
          expect(request.data, draft.toJson(memberId));
          return jsonResponse(
            envelope({
              'subscription': fullSubscription(),
              'payment': paymentJson()
                ..addAll({
                  'paymentMethod': method.wireValue,
                  'transactionReference': payment.reference.isEmpty
                      ? null
                      : payment.reference,
                }),
            }),
            status: 201,
          );
        });
        expect(
          (await repository.purchase(gymA, memberId, draft)).payment!.method,
          method,
        );
      },
    );
  }
  test('M23 cancel is member-scoped and trims optional reason', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'POST');
      expect(
        request.uri.path,
        '/api/v1/gyms/$gymA/members/$memberId/memberships/$subscriptionId/cancel',
      );
      expect(request.data, {'cancellationReason': 'Requested'});
      return jsonResponse(envelope(fullSubscription(cancelled: true)));
    });
    expect(
      (await repository.cancel(
        gymA,
        memberId,
        subscriptionId,
        ' Requested ',
      )).subscription.status,
      'cancelled',
    );
  });
  test(
    'empty cancellation reason omitted and already cancelled result valid',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.data, isEmpty);
        return jsonResponse(envelope(fullSubscription(cancelled: true)));
      });
      await repository.cancel(gymA, memberId, subscriptionId, ' ');
    },
  );
  test(
    'renew first verifies M23 ownership then posts empty M15 body',
    () async {
      final adapter = CallbackAdapter((request) {
        if (request.method == 'GET') {
          expect(
            request.uri.path,
            '/api/v1/gyms/$gymA/members/$memberId/memberships/$subscriptionId',
          );
          return jsonResponse(
            envelope({
              'subscription': fullSubscription(),
              'paymentSummary': {
                'totalSuccessfulPaidPaise': 303,
                'remainingBalancePaise': 149697,
              },
            }),
          );
        }
        expect(
          request.uri.path,
          '/api/v1/gyms/$gymA/subscriptions/$subscriptionId/renew',
        );
        expect(request.data, isEmpty);
        return jsonResponse(
          envelope(
            fullSubscription()..addAll({
              'id': '000000000000000000000088',
              'previousSubscriptionId': subscriptionId,
            }),
          ),
          status: 201,
        );
      });
      client.httpClientAdapter = adapter;
      expect(
        (await repository.renew(
          gymA,
          memberId,
          subscriptionId,
        )).subscription.previousId,
        subscriptionId,
      );
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST']);
    },
  );
  test('failed renewal ownership check never sends write', () async {
    final adapter = CallbackAdapter(
      (request) => jsonResponse(
        envelope({
          'subscription': fullSubscription()..['memberId'] = gymB,
          'paymentSummary': {
            'totalSuccessfulPaidPaise': 0,
            'remainingBalancePaise': 0,
          },
        }),
      ),
    );
    client.httpClientAdapter = adapter;
    await expectLater(
      repository.renew(gymA, memberId, subscriptionId),
      throwsA(isA<Exception>()),
    );
    expect(adapter.requests.length, 1);
    expect(adapter.requests.single.method, 'GET');
  });
  for (final scenario in [
    (400, 'VALIDATION_ERROR'),
    (401, 'INVALID_AUTHENTICATION'),
    (403, 'FORBIDDEN'),
    (409, 'SUBSCRIPTION_OVERLAP'),
    (409, 'SUBSCRIPTION_ALREADY_RENEWED'),
    (409, 'PAYMENT_OVERPAYMENT'),
    (409, 'DUPLICATE_PAYMENT_REFERENCE'),
    (500, 'INTERNAL_SERVER_ERROR'),
  ]) {
    test('write failure ${scenario.$2} is safe and classified', () async {
      final adapter = CallbackAdapter(
        (request) => jsonResponse({
          'success': false,
          'error': {'code': scenario.$2, 'message': 'PRIVATE backend detail'},
        }, status: scenario.$1),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.purchase(gymA, memberId, PurchaseDraft(planId: planId)),
        throwsA(
          isA<BillingFailure>()
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('PRIVATE')),
              )
              .having((e) => e.uncertain, 'uncertain', scenario.$1 >= 500),
        ),
      );
      expect(adapter.requests.length, 1);
    });
  }
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
  ]) {
    test('$type write outcome uncertain, never retried', () async {
      final adapter = CallbackAdapter(
        (request) => throw DioException(requestOptions: request, type: type),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.purchase(gymA, memberId, PurchaseDraft(planId: planId)),
        throwsA(
          isA<BillingFailure>().having((e) => e.uncertain, 'uncertain', true),
        ),
      );
      expect(adapter.requests.length, 1);
    });
  }
  test('read network failure is safe and not an uncertain write', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repository.plans(gymA, 1),
      throwsA(
        isA<BillingFailure>().having((e) => e.uncertain, 'uncertain', false),
      ),
    );
  });
  test(
    'malformed success / foreign scope classified uncertain after write',
    () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(
          envelope({
            'subscription': fullSubscription()..['gymId'] = gymB,
            'payment': null,
          }),
          status: 201,
        ),
      );
      await expectLater(
        repository.purchase(gymA, memberId, PurchaseDraft(planId: planId)),
        throwsA(
          isA<BillingFailure>().having((e) => e.uncertain, 'uncertain', true),
        ),
      );
    },
  );
  test(
    'foreign plan, wrong pagination and unsuccessful payment rejected',
    () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope([planJson()..['gymId'] = gymB])),
      );
      await expectLater(
        repository.plans(gymA, 1),
        throwsA(isA<BillingFailure>()),
      );
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope([], page: 2)),
      );
      await expectLater(
        repository.plans(gymA, 1),
        throwsA(isA<BillingFailure>()),
      );
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope([paymentJson()..['status'] = 'failed'])),
      );
      await expectLater(
        repository.payments(gymA, memberId, 1),
        throwsA(isA<BillingFailure>()),
      );
    },
  );
  test('invalid IDs and pagination rejected before transport', () async {
    final adapter = CallbackAdapter((_) => jsonResponse(envelope([])));
    client.httpClientAdapter = adapter;
    expect(
      () =>
          repository.purchase(gymA, '../other', PurchaseDraft(planId: planId)),
      throwsA(isA<BillingFailure>()),
    );
    expect(() => repository.plans(gymA, 0), throwsFormatException);
    expect(adapter.requests, isEmpty);
  });
  test('existing auth interceptor recovers purchase 401 once', () async {
    final api = FakeAuthApi();
    final auth = AuthRepository(api: api, storage: FakeCredentialStorage());
    addTearDown(auth.dispose);
    await auth.login(
      email: 'person@example.invalid',
      password: syntheticCredential(),
    );
    client.interceptors.add(AuthInterceptor(client: client, repository: auth));
    var calls = 0;
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.data, {'memberId': memberId, 'planId': planId});
      if (++calls == 1) {
        return jsonResponse(failureBody('INVALID_AUTHENTICATION'), status: 401);
      }
      expect(
        request.headers['Authorization'] ==
            'Bearer ${api.rotatedTokens.accessToken}',
        isTrue,
      );
      return jsonResponse(
        envelope({'subscription': fullSubscription(), 'payment': null}),
        status: 201,
      );
    });
    await repository.purchase(gymA, memberId, PurchaseDraft(planId: planId));
    expect(calls, 2);
    expect(api.refreshCalls, 1);
  });
  test(
    'management list includes inactive plans and sends pagination only',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.queryParameters, {'page': '2', 'limit': '20'});
        return jsonResponse(
          envelope([planJson()..['status'] = 'inactive'], page: 2, total: 21),
        );
      });
      expect(
        (await repository.managePlans(gymA, 2)).items.single.status,
        'inactive',
      );
    },
  );
  test('single plan GET validates gym and plan identity', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/v1/gyms/$gymA/membership-plans/$planId');
      return jsonResponse(envelope(planJson()));
    });
    expect((await repository.plan(gymA, planId)).id, planId);
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(envelope(planJson()..['id'] = gymB)),
    );
    await expectLater(
      repository.plan(gymA, planId),
      throwsA(isA<BillingFailure>()),
    );
  });
  for (final editing in [false, true]) {
    test(
      'plan ${editing ? 'PATCH' : 'POST'} matches M12 fields and zero price',
      () async {
        final draft = PlanDraft(
          name: ' Free ',
          durationDays: 30,
          pricePaise: 0,
          status: 'inactive',
        );
        client.httpClientAdapter = CallbackAdapter((request) {
          expect(request.method, editing ? 'PATCH' : 'POST');
          expect(
            request.uri.path,
            '/api/v1/gyms/$gymA/membership-plans${editing ? '/$planId' : ''}',
          );
          expect(request.data, draft.toJson(editing: editing));
          expect((request.data as Map).containsKey('gymId'), isFalse);
          return jsonResponse(
            envelope({...planJson(), ...draft.toJson(editing: editing)}),
            status: editing ? 200 : 201,
          );
        });
        expect(
          (await repository.savePlan(
            gymA,
            draft,
            planId: editing ? planId : null,
          )).pricePaise,
          0,
        );
      },
    );
  }
  for (final failure in [
    (400, 'VALIDATION_ERROR'),
    (403, 'FORBIDDEN'),
    (409, 'DUPLICATE_PLAN_NAME'),
    (500, 'INTERNAL_SERVER_ERROR'),
  ]) {
    test('plan write ${failure.$2} sanitized and not retried', () async {
      final adapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': false,
          'error': {'code': failure.$2, 'message': 'PRIVATE'},
        }, status: failure.$1),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.savePlan(
          gymA,
          PlanDraft(
            name: 'A',
            durationDays: 1,
            pricePaise: 0,
            status: 'active',
          ),
        ),
        throwsA(
          isA<BillingFailure>()
              .having((e) => e.message, 'safe', isNot(contains('PRIVATE')))
              .having((e) => e.uncertain, 'uncertain', failure.$1 >= 500),
        ),
      );
      expect(adapter.requests.length, 1);
    });
  }
  test('lost plan write response requires plan recheck', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await expectLater(
      repository.savePlan(
        gymA,
        PlanDraft(name: 'A', durationDays: 1, pricePaise: 0, status: 'active'),
      ),
      throwsA(
        isA<BillingFailure>()
            .having((e) => e.message, 'context', contains('Membership Plans'))
            .having((e) => e.uncertain, 'uncertain', true),
      ),
    );
  });
}
