import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import '../auth/auth_fakes.dart';

void main() {
  DioException responseError(int status, dynamic body) {
    final options = RequestOptions(path: 'member-onboarding/complete');
    return DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  for (final scenario in [
    ('DUPLICATE_MEMBER_CODE', 409, 'Member code already exists in this gym.'),
    (
      'DUPLICATE_PAYMENT_REFERENCE',
      409,
      'A successful payment with this reference already exists for this method in this gym.',
    ),
    (
      'IDEMPOTENCY_KEY_CONFLICT',
      409,
      'This idempotency key was already used with a different request.',
    ),
    ('PLAN_NOT_FOUND', 404, 'Membership plan not found.'),
    ('RATE_LIMITED', 429, 'Too many requests. Please try again later.'),
    ('INTERNAL_SERVER_ERROR', 500, 'An unexpected server error occurred.'),
    ('INVALID_JSON', 400, 'Request body must contain valid JSON.'),
  ]) {
    test(
      'safe diagnostics retain ${scenario.$1} status and exact public message',
      () {
        final failure = OnboardingFailure.fromDio(
          responseError(scenario.$2, {
            'success': false,
            'error': {'code': scenario.$1, 'message': scenario.$3},
          }),
        );
        final diagnostics = failure.diagnostics!;
        expect(diagnostics.httpStatus, scenario.$2);
        expect(diagnostics.code, scenario.$1);
        expect(diagnostics.serverMessage, scenario.$3);
        expect(
          diagnostics.summary,
          'HTTP ${scenario.$2} · ${scenario.$1} · ${scenario.$3}',
        );
      },
    );
  }

  for (final scenario in [
    ('DUPLICATE_MEMBER_CODE', 409),
    ('DUPLICATE_MEMBER_CODE', 500),
    ('UNKNOWN_ERROR', 409),
    ('private-token-reference', 409),
  ]) {
    test('diagnostics omit arbitrary text for ${scenario.$2} ${scenario.$1}', () {
      final failure = OnboardingFailure.fromDio(
        responseError(scenario.$2, {
          'success': false,
          'error': {
            'code': scenario.$1,
            'message':
                'synthetic-private-token password payment-reference complete-request-body',
          },
        }),
      );
      expect(failure.diagnostics!.httpStatus, scenario.$2);
      expect(failure.diagnostics!.serverMessage, isNull);
      expect(
        failure.diagnostics!.code,
        scenario == ('DUPLICATE_MEMBER_CODE', 409)
            ? 'DUPLICATE_MEMBER_CODE'
            : null,
      );
      expect(
        failure.diagnostics!.summary,
        isNot(contains('synthetic-private-token')),
      );
      expect(failure.toString(), isNot(contains('payment-reference')));
    });
  }

  test('malformed response diagnostics retain only a valid HTTP status', () {
    for (final body in [
      null,
      'private response',
      {
        'success': true,
        'error': {'code': 'DUPLICATE_MEMBER_CODE'},
      },
      {'success': false, 'error': []},
    ]) {
      final diagnostics = OnboardingDiagnostics.fromResponse(409, body);
      expect(diagnostics.summary, 'HTTP 409');
      expect(diagnostics.code, isNull);
      expect(diagnostics.serverMessage, isNull);
    }
    expect(OnboardingDiagnostics.fromResponse(999, null).summary, isEmpty);
    expect(OnboardingDiagnostics.fromResponse(null, null).summary, isEmpty);
  });

  for (final scenario in [
    (400, 'VALIDATION_ERROR', OnboardingFailureKind.validation),
    (400, 'INVALID_JSON', OnboardingFailureKind.validation),
    (400, 'PAYMENT_MEMBER_MISMATCH', OnboardingFailureKind.validation),
    (413, 'PAYLOAD_TOO_LARGE', OnboardingFailureKind.validation),
    (415, 'UNSUPPORTED_ENCODING', OnboardingFailureKind.validation),
    (401, 'INVALID_AUTHENTICATION', OnboardingFailureKind.authorization),
    (401, 'INVALID_CREDENTIALS', OnboardingFailureKind.authorization),
    (403, 'FORBIDDEN', OnboardingFailureKind.authorization),
    (403, 'CORS_ORIGIN_DENIED', OnboardingFailureKind.authorization),
    (404, 'PLAN_NOT_FOUND', OnboardingFailureKind.resourceNotFound),
    (404, 'BRANCH_NOT_FOUND', OnboardingFailureKind.resourceNotFound),
    (404, 'MEMBER_NOT_FOUND', OnboardingFailureKind.resourceNotFound),
    (404, 'SUBSCRIPTION_NOT_FOUND', OnboardingFailureKind.resourceNotFound),
    (404, 'NOT_FOUND', OnboardingFailureKind.configuration),
    (409, 'IDEMPOTENCY_KEY_CONFLICT', OnboardingFailureKind.conflict),
    (409, 'DUPLICATE_MEMBER_CODE', OnboardingFailureKind.conflict),
    (409, 'DUPLICATE_PAYMENT_REFERENCE', OnboardingFailureKind.conflict),
    (409, 'PAYMENT_OVERPAYMENT', OnboardingFailureKind.conflict),
    (409, 'PAYMENT_SUBSCRIPTION_CANCELLED', OnboardingFailureKind.conflict),
    (409, 'SUBSCRIPTION_OVERLAP', OnboardingFailureKind.conflict),
    (429, 'RATE_LIMITED', OnboardingFailureKind.rateLimited),
    (
      503,
      'ONBOARDING_STORAGE_UNAVAILABLE',
      OnboardingFailureKind.storageUnavailable,
    ),
  ]) {
    test('${scenario.$1} ${scenario.$2} is a defined rejection', () {
      final failure = OnboardingFailure.fromDio(
        responseError(scenario.$1, failureBody(scenario.$2)),
      );
      expect(failure.kind, scenario.$3);
      expect(failure.uncertain, isFalse);
      final rejection = failure.backendRejection!;
      expect(rejection.code.wireValue, scenario.$2);
      expect(rejection.status, scenario.$1);
      expect(
        rejection.establishesAttemptNonCommit,
        scenario.$2 != 'IDEMPOTENCY_KEY_CONFLICT',
      );
      final restored = OnboardingBackendRejection.fromJson(rejection.toJson());
      expect(restored.code, rejection.code);
      expect(restored.status, rejection.status);
    });
  }

  for (final status in [400, 401, 403, 404, 409, 429]) {
    test('unknown code at $status does not prove rejection', () {
      final failure = OnboardingFailure.fromDio(
        responseError(status, failureBody('UNKNOWN_ERROR')),
      );
      expect(failure.kind, OnboardingFailureKind.unexpectedResponse);
      expect(failure.uncertain, isTrue);
      expect(failure.backendRejection, isNull);
    });
  }

  for (final scenario in [
    (400, 'PLAN_NOT_FOUND'),
    (404, 'RATE_LIMITED'),
    (429, 'ONBOARDING_STORAGE_UNAVAILABLE'),
    (409, 'VALIDATION_ERROR'),
  ]) {
    test('mismatched ${scenario.$1} ${scenario.$2} remains uncertain', () {
      final failure = OnboardingFailure.fromDio(
        responseError(scenario.$1, failureBody(scenario.$2)),
      );
      expect(failure.kind, OnboardingFailureKind.unexpectedResponse);
      expect(failure.uncertain, isTrue);
      expect(failure.backendRejection, isNull);
    });
  }

  for (final code in [
    'INTERNAL_SERVER_ERROR',
    'PLAN_NOT_FOUND',
    'RATE_LIMITED',
    'ONBOARDING_STORAGE_UNAVAILABLE',
    'UNKNOWN_ERROR',
  ]) {
    test('500 $code cannot establish rollback', () {
      final failure = OnboardingFailure.fromDio(
        responseError(500, failureBody(code)),
      );
      expect(failure.kind, OnboardingFailureKind.server);
      expect(failure.uncertain, isTrue);
      expect(failure.backendRejection, isNull);
    });
  }

  test('malformed or success envelopes cannot establish a rejection', () {
    for (final body in [
      null,
      'unreadable response',
      <String, dynamic>{},
      {
        'error': {'code': 'PLAN_NOT_FOUND'},
      },
      {
        'success': true,
        'error': {'code': 'PLAN_NOT_FOUND'},
      },
      {'success': false, 'error': 'PLAN_NOT_FOUND'},
      {
        'success': false,
        'error': {'code': 404},
      },
    ]) {
      final failure = OnboardingFailure.fromDio(responseError(404, body));
      expect(failure.kind, OnboardingFailureKind.unexpectedResponse);
      expect(failure.uncertain, isTrue);
      expect(failure.backendRejection, isNull);
    }
  });

  test('an unknown wrapped exception remains uncertain', () {
    final failure = OnboardingFailure.fromDio(
      DioException(
        requestOptions: RequestOptions(path: 'member-onboarding/complete'),
        error: StateError('Synthetic internal detail'),
      ),
    );
    expect(failure.kind, OnboardingFailureKind.network);
    expect(failure.uncertain, isTrue);
    expect(failure.backendRejection, isNull);
    expect(failure.toString(), isNot(contains('Synthetic internal detail')));
  });

  test('wrapped auth cause takes precedence over an unrelated response', () {
    final error = responseError(401, failureBody('INVALID_AUTHENTICATION'));
    final failure = OnboardingFailure.fromDio(
      error.copyWith(error: const AuthFailure(AuthFailureKind.server)),
    );
    expect(failure.kind, OnboardingFailureKind.server);
    expect(failure.uncertain, isTrue);
    expect(failure.backendRejection, isNull);
  });

  test('raw backend details never enter safe failures', () {
    final body = failureBody('PLAN_NOT_FOUND');
    (body['error'] as Map)['message'] = 'Synthetic internal detail';
    final failure = OnboardingFailure.fromDio(responseError(404, body));
    expect(failure.message, isNot(contains('Synthetic internal detail')));
    expect(failure.toString(), isNot(contains('Synthetic internal detail')));
  });
  for (final kind in AuthFailureKind.values) {
    test('wrapped $kind supplies no backend rejection evidence', () {
      final failure = OnboardingFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(path: 'member-onboarding/complete'),
          error: AuthFailure(kind),
        ),
      );
      expect(failure.backendRejection, isNull);
      expect(failure.uncertain, isTrue);
    });
  }
  test('generic categories do not create rejection evidence', () {
    for (final kind in OnboardingFailureKind.values) {
      expect(OnboardingFailure(kind).backendRejection, isNull);
    }
  });
  test(
    'typed evidence rejects unknown types, codes, fields and mismatches',
    () {
      for (final evidence in [
        {'type': 'authFailure', 'code': 'PLAN_NOT_FOUND', 'status': 404},
        {'type': 'backendRejection', 'code': 'UNKNOWN_ERROR', 'status': 404},
        {'type': 'backendRejection', 'code': 'PLAN_NOT_FOUND', 'status': 400},
        {'type': 'backendRejection', 'code': 'PLAN_NOT_FOUND', 'status': 404.0},
        {'type': 'backendRejection', 'code': 'PLAN_NOT_FOUND', 'status': '404'},
        {'type': 'backendRejection', 'code': 'PLAN_NOT_FOUND'},
        {
          'type': 'backendRejection',
          'code': 'PLAN_NOT_FOUND',
          'status': 404,
          'message': 'internal detail',
        },
      ]) {
        expect(
          () => OnboardingBackendRejection.fromJson(evidence),
          throwsFormatException,
        );
      }
    },
  );
}
