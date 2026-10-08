import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/trainers/data/trainer_failure.dart';
import 'package:gym_management_app/features/trainers/data/trainer_repository.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'trainer_fakes.dart';

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
  late DioTrainerRepository repository;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioTrainerRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'list endpoint sends search/status/page and consumes meta.pagination',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/trainers');
        expect(request.method, 'GET');
        expect(request.queryParameters, {
          'page': '2',
          'limit': '20',
          'search': 'Strength',
          'status': 'inactive',
        });
        return jsonResponse(envelope([trainerJson()], page: 2, total: 21));
      });
      expect(
        (await repository.list(
          gymA,
          TrainerListQuery(
            page: 2,
            search: ' Strength ',
            status: TrainerStatus.inactive,
          ),
        )).pagination.total,
        21,
      );
    },
  );
  test('blank filters omitted and empty page accepted', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.queryParameters, {'page': '1', 'limit': '20'});
      return jsonResponse(envelope([], total: 0));
    });
    expect((await repository.list(gymA, TrainerListQuery())).trainers, isEmpty);
  });
  test('detail uses exact gym and trainer scope', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.uri.path, '/api/v1/gyms/$gymA/trainers/$trainerId');
      return jsonResponse(envelope(trainerJson()));
    });
    expect((await repository.get(gymA, trainerId)).trainerCode, 'TR01');
  });
  test('creation POST uses collection route and returns server DTO', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/gyms/$gymA/trainers');
      expect(request.data, draft().toJson(editing: false));
      return jsonResponse(envelope(trainerJson()), status: 201);
    });
    expect((await repository.create(gymA, draft())).id, trainerId);
  });
  test('PATCH sends mutable profile data only', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(request.method, 'PATCH');
      expect(request.uri.path, '/api/v1/gyms/$gymA/trainers/$trainerId');
      expect(request.data, draft(firstName: 'Updated').toJson(editing: true));
      return jsonResponse(envelope(trainerJson(firstName: 'Updated')));
    });
    expect(
      (await repository.update(
        gymA,
        trainerId,
        draft(firstName: 'Updated'),
      )).firstName,
      'Updated',
    );
  });
  for (final scenario in [
    (status: 400, code: 'VALIDATION_ERROR', phrase: 'validate'),
    (status: 401, code: 'INVALID_AUTHENTICATION', phrase: 'session'),
    (status: 403, code: 'FORBIDDEN', phrase: 'permitted'),
    (status: 404, code: 'TRAINER_NOT_FOUND', phrase: 'no longer'),
    (status: 409, code: 'DUPLICATE_TRAINER_CODE', phrase: 'already exists'),
    (status: 429, code: 'RATE_LIMITED', phrase: 'Too many'),
    (status: 500, code: 'INTERNAL_SERVER_ERROR', phrase: 'temporarily'),
  ]) {
    test('HTTP ${scenario.status} sanitized error', () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': false,
          'error': {'code': scenario.code, 'message': 'private backend detail'},
        }, status: scenario.status),
      );
      await expectLater(
        repository.create(gymA, draft()),
        throwsA(
          isA<TrainerFailure>()
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
  test('network failure marks save potentially sent', () async {
    client.httpClientAdapter = CallbackAdapter(
      (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      repository.create(gymA, draft()),
      throwsA(
        isA<TrainerFailure>().having(
          (e) => e.possiblySent,
          'ambiguous',
          isTrue,
        ),
      ),
    );
  });
  test(
    'foreign gym, wrong trainer and mismatched pagination rejected',
    () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope([trainerJson(gymId: gymB)])),
      );
      await expectLater(
        repository.list(gymA, TrainerListQuery()),
        throwsA(isA<TrainerFailure>()),
      );
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope(trainerJson()..['id'] = gymB)),
      );
      await expectLater(
        repository.get(gymA, trainerId),
        throwsA(isA<TrainerFailure>()),
      );
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(envelope([trainerJson()], page: 2)),
      );
      await expectLater(
        repository.list(gymA, TrainerListQuery()),
        throwsA(isA<TrainerFailure>()),
      );
    },
  );
  test('malformed envelope never fabricates trainer data', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse({'success': true, 'data': []}),
    );
    await expectLater(
      repository.list(gymA, TrainerListQuery()),
      throwsA(isA<TrainerFailure>()),
    );
  });
  test('invalid inputs never reach transport', () async {
    final adapter = CallbackAdapter(
      (_) => jsonResponse(envelope(trainerJson())),
    );
    client.httpClientAdapter = adapter;
    await expectLater(
      repository.get(gymA, '../other'),
      throwsA(isA<TrainerFailure>()),
    );
    await expectLater(
      repository.create(gymA, draft(firstName: '')),
      throwsA(isA<TrainerFailure>()),
    );
    expect(adapter.requests, isEmpty);
  });
  test(
    'existing interceptor recovers and replays create exactly once',
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
        return jsonResponse(envelope(trainerJson()), status: 201);
      });
      expect((await repository.create(gymA, draft())).id, trainerId);
      expect(calls, 2);
      expect(api.refreshCalls, 1);
    },
  );
}
