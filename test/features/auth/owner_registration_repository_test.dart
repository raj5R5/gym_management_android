import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/features/auth/data/owner_registration_repository.dart';
import 'package:gym_management_app/features/auth/data/owner_registration_failure.dart';
import 'package:gym_management_app/features/auth/models/owner_registration.dart';
import 'auth_fakes.dart';

void main() {
  late Dio client;
  late DioOwnerRegistrationRepository repository;
  OwnerRegistrationRequest input() => OwnerRegistrationRequest(
    ownerFullName: 'Alex River',
    email: 'owner@example.invalid',
    password: syntheticCredential(),
    gymName: 'Example Gym',
  );
  setUp(() {
    client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
    );
    repository = DioOwnerRegistrationRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'uses normal public endpoint without stale credentials, redirects, confirmation password or identity claims',
    () async {
      client.options.headers.addAll({
        'Authorization': 'private-header',
        'Cookie': 'private-cookie',
        'Origin': 'https://stale.invalid',
      });
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.uri.path, '/api/v1/auth/register-owner');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], isNull);
        expect(request.headers['Cookie'], isNull);
        expect(request.headers['Origin'], isNull);
        expect(request.followRedirects, isFalse);
        expect(request.extra['authRequired'], isFalse);
        expect((request.data as Map).keys.toSet(), {
          'ownerFullName',
          'email',
          'password',
          'gymName',
        });
        return jsonResponse(
          success({'accountCreated': true, 'gymCreated': true}),
          status: 201,
        );
      });
      await repository.register(input());
    },
  );
  for (final scenario in [
    (
      status: 409,
      code: 'DUPLICATE_EMAIL',
      kind: OwnerRegistrationFailureKind.duplicateEmail,
    ),
    (
      status: 409,
      code: 'DUPLICATE_GYM_NAME',
      kind: OwnerRegistrationFailureKind.duplicateGym,
    ),
    (
      status: 400,
      code: 'VALIDATION_ERROR',
      kind: OwnerRegistrationFailureKind.validation,
    ),
    (
      status: 429,
      code: 'RATE_LIMITED',
      kind: OwnerRegistrationFailureKind.rateLimited,
    ),
    (
      status: 503,
      code: 'OWNER_REGISTRATION_STORAGE_UNAVAILABLE',
      kind: OwnerRegistrationFailureKind.unavailable,
    ),
    (
      status: 500,
      code: 'INTERNAL_SERVER_ERROR',
      kind: OwnerRegistrationFailureKind.unexpected,
    ),
  ]) {
    test(
      'maps ${scenario.code} without using private/raw server messages',
      () async {
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': false,
            'error': {
              'code': scenario.code,
              'message': 'private password and gym documents must never appear',
            },
          }, status: scenario.status),
        );
        await expectLater(
          repository.register(input()),
          throwsA(
            isA<OwnerRegistrationFailure>()
                .having((failure) => failure.kind, 'kind', scenario.kind)
                .having(
                  (failure) => failure.toString().contains('private password'),
                  'safe diagnostics',
                  false,
                ),
          ),
        );
      },
    );
  }
  test(
    'network failure explains uncertain outcome and never automatically repeats registration',
    () async {
      var calls = 0;
      client.httpClientAdapter = CallbackAdapter((request) {
        calls++;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        );
      });
      await expectLater(
        repository.register(input()),
        throwsA(
          isA<OwnerRegistrationFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                OwnerRegistrationFailureKind.network,
              )
              .having(
                (failure) => failure.message.contains('sign in normally'),
                'lost-response recovery',
                true,
              ),
        ),
      );
      expect(calls, 1);
    },
  );
  test(
    'unconfigured transport reports configuration without a request',
    () async {
      client.close(force: true);
      client = createApiClient(AppConfig.fromValues());
      repository = DioOwnerRegistrationRepository(client);
      await expectLater(
        repository.register(input()),
        throwsA(
          isA<OwnerRegistrationFailure>().having(
            (failure) => failure.kind,
            'kind',
            OwnerRegistrationFailureKind.configuration,
          ),
        ),
      );
    },
  );
  test('unexpected confirmation fails safely', () async {
    client.httpClientAdapter = CallbackAdapter(
      (_) => jsonResponse(success({'accountCreated': true}), status: 201),
    );
    await expectLater(
      repository.register(input()),
      throwsA(
        isA<OwnerRegistrationFailure>().having(
          (failure) => failure.kind,
          'kind',
          OwnerRegistrationFailureKind.unexpected,
        ),
      ),
    );
  });
}
