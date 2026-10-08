import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:gym_management_app/features/members/data/member_repository.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';

Map<String, dynamic> envelope(
  Object? data, {
  int page = 1,
  int total = 1,
  int limit = 20,
}) => {
  'success': true,
  'data': data,
  'meta': {
    'requestId': 'synthetic-request',
    'pagination': {'page': page, 'limit': limit, 'total': total},
  },
};
void main() {
  late Dio client;
  late DioMemberRepository repository;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioMemberRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'list sends backend search/status/pagination and reads meta pagination',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/members');
        expect(request.method, 'GET');
        expect(request.queryParameters, {
          'page': '2',
          'limit': '20',
          'search': 'Alex',
          'status': 'active',
        });
        return jsonResponse(envelope([profileJson()], page: 2, total: 21));
      });
      final result = await repository.list(
        gymA,
        MemberListQuery(page: 2, search: ' Alex ', status: MemberStatus.active),
      );
      expect(result.pagination.total, 21);
      expect(result.pagination.hasPrevious, isTrue);
      expect(result.pagination.hasNext, isFalse);
    },
  );
  test('blank search and status are omitted; empty page is valid', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.queryParameters, {'page': '1', 'limit': '20'});
      return jsonResponse(envelope([], total: 0));
    });
    expect((await repository.list(gymA, MemberListQuery())).members, isEmpty);
  });
  test('member GET is scoped to gym and member', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.uri.path, '/api/v1/gyms/$gymA/members/$memberId');
      return jsonResponse(envelope(profileJson()));
    });
    expect((await repository.get(gymA, memberId)).memberCode, 'ME01');
  });
  test(
    'member 360 summary is one request with no redundant profile fetch',
    () async {
      final adapter = CallbackAdapter((request) {
        expect(
          request.uri.path,
          '/api/v1/gyms/$gymA/members/$memberId/summary',
        );
        expect(request.queryParameters, isEmpty);
        return jsonResponse(envelope(summaryJson(populated: true)));
      });
      client.httpClientAdapter = adapter;
      expect(
        (await repository.summary(gymA, memberId)).currentPayments!.paidPaise,
        303,
      );
      expect(adapter.requests.length, 1);
    },
  );
  test('onboarding POST uses M21 allowlist and actual created DTO', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/gyms/$gymA/member-onboarding');
      expect(request.data, draft().toJson(editing: false));
      return jsonResponse(envelope(profileJson()), status: 201);
    });
    expect((await repository.onboard(gymA, draft())).id, memberId);
  });
  test(
    'PATCH uses mutable fields only and preserves branch by omission',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/api/v1/gyms/$gymA/members/$memberId');
        expect(request.data, draft(firstName: 'Updated').toJson(editing: true));
        for (final key in ['gymId', 'userId', 'memberCode', 'branchId']) {
          expect((request.data as Map).containsKey(key), isFalse);
        }
        return jsonResponse(envelope(profileJson(firstName: 'Updated')));
      });
      expect(
        (await repository.update(
          gymA,
          memberId,
          draft(firstName: 'Updated'),
        )).firstName,
        'Updated',
      );
    },
  );
  test(
    'M23 history sends backend page/limit and parses enriched payments',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(
          request.uri.path,
          '/api/v1/gyms/$gymA/members/$memberId/memberships',
        );
        expect(request.queryParameters, {'page': '2', 'limit': '20'});
        return jsonResponse(
          envelope(historyJson(populated: true), page: 2, total: 21),
        );
      });
      expect(
        (await repository.memberships(
          gymA,
          memberId,
          2,
        )).subscriptions.single.payments!.balancePaise,
        149697,
      );
    },
  );
  test('membership GET reads cancellation metadata without mutation', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'GET');
      expect(
        request.uri.path,
        '/api/v1/gyms/$gymA/members/$memberId/memberships/$subscriptionId',
      );
      return jsonResponse(
        envelope({
          'subscription': subscriptionJson(cancelled: true)
            ..addAll({
              'gymId': gymA,
              'memberId': memberId,
              'cancelledAt': '2026-03-03T12:00:00Z',
              'cancellationReason': 'Requested',
            }),
          'paymentSummary': {
            'totalSuccessfulPaidPaise': 303,
            'remainingBalancePaise': 149697,
          },
        }),
      );
    });
    expect(
      (await repository.membership(
        gymA,
        memberId,
        subscriptionId,
      )).subscription.cancellationReason,
      'Requested',
    );
  });
  for (final scenario in [
    (status: 400, code: 'VALIDATION_ERROR', phrase: 'validate'),
    (status: 401, code: 'INVALID_AUTHENTICATION', phrase: 'session'),
    (status: 403, code: 'FORBIDDEN', phrase: 'permitted'),
    (status: 404, code: 'MEMBER_NOT_FOUND', phrase: 'no longer'),
    (status: 409, code: 'DUPLICATE_MEMBER_CODE', phrase: 'already exists'),
    (status: 429, code: 'RATE_LIMITED', phrase: 'Too many'),
    (status: 500, code: 'INTERNAL_SERVER_ERROR', phrase: 'temporarily'),
  ]) {
    test('HTTP ${scenario.status} is sanitized and useful', () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': false,
          'error': {'code': scenario.code, 'message': 'private backend detail'},
        }, status: scenario.status),
      );
      await expectLater(
        repository.onboard(gymA, draft()),
        throwsA(
          isA<MemberFailure>()
              .having((e) => e.message, 'message', contains(scenario.phrase))
              .having(
                (e) => e.message,
                'sanitized',
                isNot(contains('private')),
              ),
        ),
      );
    });
  }
  test('network failure is safe', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repository.list(gymA, MemberListQuery()),
      throwsA(
        isA<MemberFailure>().having(
          (e) => e.message,
          'message',
          contains('connection'),
        ),
      ),
    );
  });
  test('foreign gym DTO rejected', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(envelope([profileJson(gymId: gymB)])),
    );
    await expectLater(
      repository.list(gymA, MemberListQuery()),
      throwsA(isA<MemberFailure>()),
    );
  });
  test('wrong summary member rejected', () async {
    final json = summaryJson();
    (json['member'] as Map)['id'] = gymB;
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(envelope(json)),
    );
    await expectLater(
      repository.summary(gymA, memberId),
      throwsA(isA<MemberFailure>()),
    );
  });
  test('malformed pagination/envelope rejected', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse({
        'success': true,
        'data': [profileJson()],
      }),
    );
    await expectLater(
      repository.list(gymA, MemberListQuery()),
      throwsA(isA<MemberFailure>()),
    );
  });
  test(
    'onboarding uses existing interceptor recovery and replays once',
    () async {
      final api = FakeAuthApi();
      final auth = AuthRepository(api: api, storage: FakeCredentialStorage());
      addTearDown(auth.dispose);
      await auth.login(
        email: 'person@example.invalid',
        password: syntheticCredential(),
      );
      client.interceptors.add(
        AuthInterceptor(client: client, repository: auth),
      );
      var calls = 0;
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.data, draft().toJson(editing: false));
        if (++calls == 1) {
          return jsonResponse(
            failureBody('INVALID_AUTHENTICATION'),
            status: 401,
          );
        }
        expect(
          request.headers['Authorization'] ==
              'Bearer ${api.rotatedTokens.accessToken}',
          isTrue,
        );
        return jsonResponse(envelope(profileJson()), status: 201);
      });
      expect((await repository.onboard(gymA, draft())).id, memberId);
      expect(calls, 2);
      expect(api.refreshCalls, 1);
    },
  );
  test('invalid IDs or input never reach transport', () async {
    final adapter = CallbackAdapter(
      (_) => jsonResponse(envelope(profileJson())),
    );
    client.httpClientAdapter = adapter;
    await expectLater(
      repository.get(gymA, '../other'),
      throwsA(isA<MemberFailure>()),
    );
    await expectLater(
      repository.onboard(gymA, draft(firstName: ' ')),
      throwsA(isA<MemberFailure>()),
    );
    expect(adapter.requests, isEmpty);
  });
}
