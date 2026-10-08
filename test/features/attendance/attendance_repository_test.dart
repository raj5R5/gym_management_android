import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/data/auth_interceptor.dart';
import 'package:gym_management_app/features/attendance/data/attendance_repository.dart';
import 'package:gym_management_app/features/attendance/data/attendance_failure.dart';
import 'package:gym_management_app/features/attendance/models/attendance_models.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'attendance_fakes.dart';

void main() {
  late Dio client;
  late DioAttendanceRepository repository;
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioAttendanceRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'M19 today sends server filters/page without branch/local date',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/attendance/today');
        expect(request.queryParameters, {
          'page': '2',
          'limit': '20',
          'status': 'completed',
          'memberId': memberId,
        });
        return jsonResponse(attendanceEnvelope(todayJson(), page: 2));
      });
      expect(
        (await repository.today(
          gymA,
          AttendanceQuery(
            page: 2,
            status: VisitStatus.completed,
            memberId: memberId,
          ),
        )).timezone,
        'America/New_York',
      );
    },
  );
  test(
    'M16 open list has no date filter so overnight visits remain actionable',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/gyms/$gymA/attendance');
        expect(request.queryParameters, {
          'page': '1',
          'limit': '20',
          'status': 'open',
        });
        return jsonResponse(
          attendanceEnvelope([
            visitJson()..['checkInAt'] = '2026-01-01T00:00:00Z',
          ]),
        );
      });
      expect(
        (await repository.openVisits(gymA, 1)).visits.single.checkInAt.year,
        2026,
      );
    },
  );
  test(
    'check-in uses only scoped member and assigned branch; no timestamp/subscription input',
    () async {
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/gyms/$gymA/attendance/check-in');
        expect(request.data, {'memberId': memberId, 'branchId': branchId});
        return jsonResponse(attendanceEnvelope(visitJson()), status: 201);
      });
      final member = MemberProfile.fromJson(
        profileJson()..['branchId'] = branchId,
      );
      expect((await repository.checkIn(gymA, member)).status, VisitStatus.open);
    },
  );
  test(
    'branchless member sends no write and explains deferred branch management',
    () async {
      final adapter = CallbackAdapter(
        (_) => jsonResponse(attendanceEnvelope(visitJson())),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.checkIn(gymA, MemberProfile.fromJson(profileJson())),
        throwsA(
          isA<AttendanceFailure>().having(
            (e) => e.message,
            'reason',
            contains('no assigned branch'),
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    },
  );
  test('checkout body is empty and server duration preserved', () async {
    client.httpClientAdapter = CallbackAdapter((request) {
      expect(
        request.uri.path,
        '/api/v1/gyms/$gymA/attendance/$visitId/check-out',
      );
      expect(request.data, isEmpty);
      return jsonResponse(attendanceEnvelope(visitJson(completed: true)));
    });
    expect((await repository.checkOut(gymA, visitId)).durationMs, 4500000);
  });
  for (final code in [
    'ATTENDANCE_ALREADY_OPEN',
    'ATTENDANCE_NOT_OPEN',
    'ATTENDANCE_MEMBERSHIP_REQUIRED',
    'ATTENDANCE_MEMBERSHIP_AMBIGUOUS',
    'ATTENDANCE_BRANCH_INACTIVE',
    'ATTENDANCE_BRANCH_MISMATCH',
    'ATTENDANCE_NOT_FOUND',
    'MEMBER_NOT_FOUND',
    'FORBIDDEN',
    'INVALID_AUTHENTICATION',
    'VALIDATION_ERROR',
  ]) {
    test('structured $code failure sanitized', () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(
          {
            'success': false,
            'error': {'code': code, 'message': 'PRIVATE diagnostic'},
          },
          status: code == 'INVALID_AUTHENTICATION'
              ? 401
              : code == 'FORBIDDEN'
              ? 403
              : 409,
        ),
      );
      await expectLater(
        repository.checkOut(gymA, visitId),
        throwsA(
          isA<AttendanceFailure>()
              .having((e) => e.message, 'safe', isNot(contains('PRIVATE')))
              .having((e) => e.uncertain, 'certain rejection', false),
        ),
      );
    });
  }
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('write $type is uncertain without automatic retry', () async {
      final adapter = CallbackAdapter(
        (request) => throw DioException(requestOptions: request, type: type),
      );
      client.httpClientAdapter = adapter;
      await expectLater(
        repository.checkOut(gymA, visitId),
        throwsA(
          isA<AttendanceFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(adapter.requests.length, 1);
    });
  }
  test('malformed or foreign-scope success is uncertain after write', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(
        attendanceEnvelope(visitJson(completed: true)..['gymId'] = gymB),
      ),
    );
    await expectLater(
      repository.checkOut(gymA, visitId),
      throwsA(
        isA<AttendanceFailure>().having((e) => e.uncertain, 'uncertain', true),
      ),
    );
  });
  test('wrong pagination or member filter fails safely', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(attendanceEnvelope(todayJson(), page: 2)),
    );
    await expectLater(
      repository.today(gymA, AttendanceQuery()),
      throwsA(isA<AttendanceFailure>()),
    );
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(attendanceEnvelope(todayJson())),
    );
    await expectLater(
      repository.today(gymA, AttendanceQuery(memberId: gymB)),
      throwsA(isA<AttendanceFailure>()),
    );
  });
  test(
    'attendance uses existing authenticated 401 refresh and one replay',
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
      var attempts = 0;
      client.httpClientAdapter = CallbackAdapter((request) {
        attempts++;
        if (attempts == 1) {
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
        return jsonResponse(attendanceEnvelope(todayJson()));
      });
      expect(
        (await repository.today(gymA, AttendanceQuery())).visits.length,
        1,
      );
      expect(api.refreshCalls, 1);
      expect(attempts, 2);
    },
  );
}
