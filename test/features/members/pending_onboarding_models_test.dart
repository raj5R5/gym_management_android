import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'onboarding_fakes.dart';

Map<String, dynamic> attemptJson(
  int number,
  String outcome, {
  String? code,
  int status = 404,
}) => {
  'number': number,
  'dispatchedAt': '2026-01-01T10:00:00.123456Z',
  'outcome': outcome,
  if (code != null)
    'rejection': {'type': 'backendRejection', 'code': code, 'status': status},
};

Map<String, dynamic> recordJson({
  List<Map<String, dynamic>> attempts = const [],
  String status = 'prepared',
  int revision = 0,
}) => {
  ...jsonDecode(pendingOperation().encode()) as Map<String, dynamic>,
  'version': 2,
  'createdAt': '2026-01-01T00:00:00Z',
  'revision': revision,
  'attempts': attempts,
  'status': status,
};

void main() {
  final corrupt = throwsA(
    isA<OnboardingFailure>().having(
      (e) => e.kind,
      'kind',
      OnboardingFailureKind.corruptRecord,
    ),
  );

  test('explicit legacy fixtures retain version 1 without ledger metadata', () {
    final operation = pendingOperation();
    expect(operation.version, 1);
    expect(operation.status, PendingOnboardingStatus.pending);
    expect(operation.attempts, isEmpty);
    expect(jsonDecode(operation.encode()), isNot(contains('revision')));
  });

  test(
    'legacy decode and confirmation preserve original immutable fields exactly',
    () {
      final body = onboardingRequest(membership: true, amount: 40000).toJson();
      body['membership']['payment']['paidAt'] = '2026-01-01T10:00:00.123456Z';
      final requestJson = const JsonEncoder.withIndent('  ').convert(body);
      final json =
          jsonDecode(pendingOperation().encode()) as Map<String, dynamic>;
      json['requestJson'] = requestJson;
      json['idempotencyKey'] = 'Legacy_Original-Key12345';
      json['createdAt'] = '2026-01-01T00:00:00.123456Z';
      (json['scope'] as Map)['gymId'] = (json['scope']['gymId'] as String)
          .toUpperCase();
      final encoded = const JsonEncoder.withIndent('  ').convert(json);
      final operation = PendingOnboardingOperation.decode(encoded);
      expect(operation.encode(), encoded);
      expect(operation.request.frozenJson, requestJson);
      expect(operation.idempotencyKey, json['idempotencyKey']);
      expect(operation.createdAt.microsecond, 456);
      expect(operation.scope.toJson(), json['scope']);
      expect(operation.status, PendingOnboardingStatus.pending);
      final result = OnboardingResult.fromJson(
        onboardingResultJson(operation.request),
      );
      final confirmed = jsonDecode(operation.confirmed(result).encode()) as Map;
      for (final field in [
        'version',
        'scope',
        'requestJson',
        'idempotencyKey',
        'createdAt',
      ]) {
        expect(confirmed[field], json[field], reason: field);
      }
      expect(confirmed['status'], 'confirmed');
      expect(
        PendingOnboardingOperation.decode(
          jsonEncode(confirmed),
        ).result!.operationId,
        result.operationId,
      );
    },
  );

  final rejected = attemptJson(1, 'rejected', code: 'PLAN_NOT_FOUND');
  for (final scenario in [
    ('prepared', 0, <Map<String, dynamic>>[]),
    ('uncertain', 1, [attemptJson(1, 'unresolved')]),
    ('rejected', 2, [rejected]),
    (
      'rejected',
      4,
      [rejected, attemptJson(2, 'rejected', code: 'RATE_LIMITED', status: 429)],
    ),
    (
      'uncertain',
      3,
      [
        attemptJson(1, 'unresolved'),
        attemptJson(2, 'rejected', code: 'PLAN_NOT_FOUND'),
      ],
    ),
    ('uncertain', 3, [rejected, attemptJson(2, 'unresolved')]),
    (
      'reconciliationRequired',
      2,
      [
        attemptJson(
          1,
          'conflict',
          code: 'IDEMPOTENCY_KEY_CONFLICT',
          status: 409,
        ),
      ],
    ),
    (
      'reconciliationRequired',
      3,
      [
        attemptJson(1, 'unresolved'),
        attemptJson(
          2,
          'conflict',
          code: 'IDEMPOTENCY_KEY_CONFLICT',
          status: 409,
        ),
      ],
    ),
  ]) {
    test('v2 decodes ${scenario.$1} with ${scenario.$3.length} attempts', () {
      final json = recordJson(
        status: scenario.$1,
        revision: scenario.$2,
        attempts: scenario.$3,
      );
      final encoded = jsonEncode(json);
      final operation = PendingOnboardingOperation.decode(encoded);
      expect(operation.version, 2);
      expect(operation.revision, scenario.$2);
      expect(operation.status.name, scenario.$1);
      expect(operation.encode(), encoded);
      expect(operation.attempts.map((a) => a.toJson()).toList(), scenario.$3);
      expect(() => operation.attempts.clear(), throwsUnsupportedError);
    });
  }

  for (final previous in ['none', 'unresolved', 'rejected']) {
    test(
      'validated confirmation resolves $previous history without erasing it',
      () {
        final attempts = <Map<String, dynamic>>[
          if (previous == 'unresolved') attemptJson(1, 'unresolved'),
          if (previous == 'rejected') rejected,
          attemptJson(previous == 'none' ? 1 : 2, 'confirmed'),
        ];
        final json = recordJson(
          status: 'confirmed',
          revision: 4,
          attempts: attempts,
        );
        final request = OnboardingRequest.fromFrozenJson(
          json['requestJson'] as String,
        );
        json['result'] = onboardingResultJson(request);
        final operation = PendingOnboardingOperation.decode(jsonEncode(json));
        expect(operation.status, PendingOnboardingStatus.confirmed);
        expect(operation.result!.operationId, onboardingOperationId);
        expect(operation.attempts, hasLength(attempts.length));
        expect(operation.encode(), jsonEncode(json));
      },
    );
  }

  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'missing revision': (j) => j.remove('revision'),
    'negative revision': (j) => j['revision'] = -1,
    'fractional revision': (j) => j['revision'] = 1.5,
    'string revision': (j) => j['revision'] = '1',
    'boolean revision': (j) => j['revision'] = false,
    'prepared revision without attempts': (j) => j['revision'] = 1,
    'invalid creation timestamp': (j) =>
        j['createdAt'] = '2026-02-30T00:00:00Z',
    'missing attempts': (j) => j.remove('attempts'),
    'non-list attempts': (j) => j['attempts'] = {},
    'null attempts': (j) => j['attempts'] = null,
    'non-object attempt': (j) => j['attempts'] = ['bad'],
    'unknown root field': (j) => j['credentials'] = 'synthetic-invalid-field',
    'unknown scope field': (j) => j['scope']['extra'] = true,
    'unknown status': (j) => j['status'] = 'unknown',
    'legacy pending status': (j) => j['status'] = 'pending',
    'rejected without attempts': (j) => j['status'] = 'rejected',
    'uncertain without attempts': (j) => j['status'] = 'uncertain',
    'confirmed without result': (j) => j['status'] = 'confirmed',
    'prepared with result': (j) =>
        j['result'] = onboardingResultJson(onboardingRequest()),
    'confirmed with no attempt': (j) {
      j['status'] = 'confirmed';
      j['result'] = onboardingResultJson(onboardingRequest());
    },
  }.entries) {
    test('v2 rejects ${mutation.key}', () {
      final json = recordJson();
      mutation.value(json);
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    });
  }

  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'number zero': (a) => a['number'] = 0,
    'negative number': (a) => a['number'] = -1,
    'fractional number': (a) => a['number'] = 1.5,
    'string number': (a) => a['number'] = '1',
    'missing number': (a) => a.remove('number'),
    'missing dispatch timestamp': (a) => a.remove('dispatchedAt'),
    'invalid timestamp': (a) => a['dispatchedAt'] = 'invalid',
    'calendar overflow': (a) => a['dispatchedAt'] = '2026-02-30T10:00:00Z',
    'time overflow': (a) => a['dispatchedAt'] = '2026-01-01T25:00:00Z',
    'non-UTC timestamp': (a) => a['dispatchedAt'] = '2026-01-01T10:00:00+01:00',
    'pre-epoch timestamp': (a) => a['dispatchedAt'] = '1969-01-01T10:00:00Z',
    'unknown outcome': (a) => a['outcome'] = 'failed',
    'missing outcome': (a) => a.remove('outcome'),
    'missing rejection': (a) => a.remove('rejection'),
    'null rejection': (a) => a['rejection'] = null,
    'non-object evidence': (a) => a['rejection'] = 'PLAN_NOT_FOUND',
    'unknown evidence type': (a) => a['rejection']['type'] = 'authFailure',
    'unknown evidence code': (a) => a['rejection']['code'] = 'UNKNOWN_ERROR',
    'mismatched evidence status': (a) => a['rejection']['status'] = 429,
    'non-integer evidence status': (a) => a['rejection']['status'] = 404.0,
    'unknown evidence field': (a) => a['rejection']['headers'] = {},
    'unknown attempt field': (a) => a['extra'] = true,
    'unresolved with rejection': (a) => a['outcome'] = 'unresolved',
    'confirmed with rejection': (a) => a['outcome'] = 'confirmed',
    'conflict with non-commit evidence': (a) => a['outcome'] = 'conflict',
    'key conflict as rejection': (a) {
      a['rejection']['code'] = 'IDEMPOTENCY_KEY_CONFLICT';
      a['rejection']['status'] = 409;
    },
  }.entries) {
    test('v2 rejects attempt with ${mutation.key}', () {
      final attempt = attemptJson(1, 'rejected', code: 'PLAN_NOT_FOUND');
      mutation.value(attempt);
      final json = recordJson(
        status: 'rejected',
        revision: 2,
        attempts: [attempt],
      );
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    });
  }

  for (final scenario in [
    [attemptJson(2, 'unresolved')],
    [rejected, attemptJson(1, 'unresolved')],
    [rejected, attemptJson(3, 'unresolved')],
    [attemptJson(2, 'unresolved'), attemptJson(1, 'unresolved')],
    [attemptJson(1, 'confirmed'), attemptJson(2, 'unresolved')],
    [
      attemptJson(1, 'conflict', code: 'IDEMPOTENCY_KEY_CONFLICT', status: 409),
      attemptJson(2, 'unresolved'),
    ],
  ].indexed) {
    test('v2 rejects invalid attempt sequence ${scenario.$1}', () {
      final json = recordJson(
        status: 'uncertain',
        revision: 5,
        attempts: scenario.$2,
      );
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    });
  }

  test('later rejection cannot label unresolved history as rejected', () {
    final json = recordJson(
      status: 'rejected',
      revision: 3,
      attempts: [
        attemptJson(1, 'unresolved'),
        attemptJson(2, 'rejected', code: 'PLAN_NOT_FOUND'),
      ],
    );
    expect(() => PendingOnboardingOperation.decode(jsonEncode(json)), corrupt);
  });
  test('v2 requires revisions for dispatch and outcome writes', () {
    for (final revision in [0, 1]) {
      final json = recordJson(
        status: 'rejected',
        revision: revision,
        attempts: [rejected],
      );
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    }
  });
  test(
    'v2 requires result to match the request, scope and confirmed attempt',
    () {
      final json = recordJson(
        status: 'confirmed',
        revision: 2,
        attempts: [attemptJson(1, 'confirmed')],
      );
      json['result'] = onboardingResultJson(onboardingRequest());
      json['result']['member']['memberCode'] = 'OTHER';
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
      json['result'] = onboardingResultJson(onboardingRequest());
      json['attempts'] = [attemptJson(1, 'unresolved')];
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    },
  );
  test('legacy confirmation cannot silently discard a version 2 ledger', () {
    final operation = PendingOnboardingOperation.decode(
      jsonEncode(recordJson()),
    );
    expect(
      () => operation.confirmed(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      ),
      throwsA(
        isA<OnboardingFailure>().having(
          (e) => e.kind,
          'kind',
          OnboardingFailureKind.unsupportedVersion,
        ),
      ),
    );
  });
  test('version 1 cannot claim v2 states or attempt metadata', () {
    for (final field in [
      {'status': 'rejected'},
      {'attempts': []},
      {'revision': 0},
    ]) {
      final json =
          jsonDecode(pendingOperation().encode()) as Map<String, dynamic>;
      json.addAll(field);
      expect(
        () => PendingOnboardingOperation.decode(jsonEncode(json)),
        corrupt,
      );
    }
  });
}
