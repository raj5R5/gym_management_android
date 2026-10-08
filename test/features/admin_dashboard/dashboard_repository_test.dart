import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/admin_dashboard/data/dashboard_repository.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';

import '../auth/auth_fakes.dart';
import 'dashboard_fakes.dart';

void main() {
  late Dio client;
  late DioDashboardRepository repository;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioDashboardRepository(client);
  });
  tearDown(() => client.close(force: true));
  test('exact endpoint/envelope with default dates and no branchId', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.uri.path, '/api/v1/gyms/$gymA/dashboard');
      expect(request.method, 'GET');
      expect(request.queryParameters, isEmpty);
      return jsonResponse(success(dashboardJson()));
    });
    expect(
      (await repository.getDashboard(
        gymA,
        const DashboardQuery.today(),
      )).members.total,
      12,
    );
  });
  test('custom period sends only inclusive calendar-date parameters', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.queryParameters, {
        'from': '2026-03-01',
        'to': '2026-03-01',
      });
      return jsonResponse(success(dashboardJson()));
    });
    await repository.getDashboard(
      gymA,
      DashboardQuery.range(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 1)),
    );
  });
  test('invalid gym ID never reaches transport', () async {
    final adapter = CallbackAdapter(
      (_) => jsonResponse(success(dashboardJson())),
    );
    client.httpClientAdapter = adapter;
    await expectLater(
      repository.getDashboard('../other', const DashboardQuery.today()),
      throwsA(isA<AuthFailure>()),
    );
    expect(adapter.requests, isEmpty);
  });
  for (final status in [400, 401, 403, 500]) {
    test('HTTP $status becomes typed sanitized failure', () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(
          failureBody(status == 401 ? 'INVALID_AUTHENTICATION' : 'TEST'),
          status: status,
        ),
      );
      await expectLater(
        repository.getDashboard(gymA, const DashboardQuery.today()),
        throwsA(isA<AuthFailure>()),
      );
    });
  }
  test('malformed envelope never invents a dashboard', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse({'success': true, 'data': {}}),
    );
    await expectLater(
      repository.getDashboard(gymA, const DashboardQuery.today()),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.unexpectedResponse,
        ),
      ),
    );
  });
  test('rejects branch-filtered result being shown as all branches', () async {
    final json = dashboardJson();
    (json['period'] as Map)['branchId'] = gymB;
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(success(json)),
    );
    await expectLater(
      repository.getDashboard(gymA, const DashboardQuery.today()),
      throwsA(isA<AuthFailure>()),
    );
  });
  test('rejects response with a different requested date period', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(success(dashboardJson())),
    );
    await expectLater(
      repository.getDashboard(
        gymA,
        DashboardQuery.range(
          CalendarDate(2026, 3, 2),
          CalendarDate(2026, 3, 2),
        ),
      ),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.unexpectedResponse,
        ),
      ),
    );
  });
  test('network failure sanitized', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repository.getDashboard(gymA, const DashboardQuery.today()),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.network,
        ),
      ),
    );
  });
  test(
    'existing interceptor refreshes and retries actual dashboard request',
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
      var requests = 0;
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.queryParameters.containsKey('branchId'), isFalse);
        if (++requests == 1) {
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
        return jsonResponse(success(dashboardJson()));
      });
      await repository.getDashboard(gymA, const DashboardQuery.today());
      expect(requests, 2);
      expect(api.refreshCalls, 1);
    },
  );
}
