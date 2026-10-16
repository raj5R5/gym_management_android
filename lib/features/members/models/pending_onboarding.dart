import 'dart:convert';
import 'dart:math';

import '../../../core/config/app_config.dart';
import '../data/onboarding_failure.dart';
import 'member_models.dart';
import 'onboarding_models.dart';

class OnboardingScope {
  OnboardingScope({
    required this.environment,
    required this.apiBaseUrl,
    required this.userId,
    required this.gymId,
  }) {
    onboardingId(gymId);
    if (userId.isEmpty || userId.trim() != userId || userId.length > 128) {
      throw const FormatException('Invalid onboarding account.');
    }
    // Require the same canonical public API identity used by bootstrap.
    final config = AppConfig.fromValues(
      environmentName: environment.name,
      apiBaseUrl: apiBaseUrl,
    );
    if (config.apiBaseUrl == null ||
        config.apiBaseUrl.toString() != apiBaseUrl) {
      throw const FormatException('Invalid onboarding API scope.');
    }
  }
  factory OnboardingScope.fromConfig(
    AppConfig config, {
    required String userId,
    required String gymId,
  }) {
    if (config.apiBaseUrl == null) {
      throw const OnboardingFailure(OnboardingFailureKind.scopeMismatch);
    }
    return OnboardingScope(
      environment: config.environment,
      apiBaseUrl: config.apiBaseUrl.toString(),
      userId: userId,
      gymId: gymId,
    );
  }
  factory OnboardingScope.fromJson(Map<String, dynamic> json) =>
      OnboardingScope(
        environment: AppEnvironment.values.byName(text(json, 'environment')),
        apiBaseUrl: text(json, 'apiBaseUrl'),
        userId: text(json, 'userId'),
        gymId: text(json, 'gymId'),
      );
  final AppEnvironment environment;
  final String apiBaseUrl, userId, gymId;
  Map<String, dynamic> toJson() => {
    'environment': environment.name,
    'apiBaseUrl': apiBaseUrl,
    'userId': userId,
    'gymId': gymId,
  };
  bool matches(OnboardingScope? other) =>
      other != null &&
      environment == other.environment &&
      apiBaseUrl == other.apiBaseUrl &&
      userId == other.userId &&
      gymId.toLowerCase() == other.gymId.toLowerCase();
  String get storageKey =>
      'gym.onboarding.v1.${environment.name}.'
      '${Uri.encodeComponent(apiBaseUrl)}.${Uri.encodeComponent(userId)}.${gymId.toLowerCase()}.pending';
}

enum PendingOnboardingStatus {
  pending, // Version 1: no attempt history is available.
  confirmed,
  prepared,
  uncertain,
  rejected,
  reconciliationRequired,
}

enum OnboardingAttemptOutcome { unresolved, rejected, conflict, confirmed }

void _recordShape(
  Map<String, dynamic> json,
  Set<String> required,
  Set<String> optional,
) {
  final keys = json.keys.toSet();
  if (!keys.containsAll(required) ||
      keys.difference({...required, ...optional}).isNotEmpty) {
    throw const FormatException('Invalid onboarding record fields.');
  }
}

DateTime _dispatchTimestamp(String value) {
  // Ledger timestamps are UTC instants. Do not silently accept calendar overflow.
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
  ).hasMatch(value)) {
    throw const FormatException('Invalid dispatch timestamp.');
  }
  final parsed = DateTime.parse(value);
  final seconds = value.replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
  if (parsed.isBefore(DateTime.utc(1970)) ||
      '${parsed.toIso8601String().split('.').first}Z' != seconds) {
    throw const FormatException('Invalid dispatch timestamp.');
  }
  return parsed;
}

/// One dispatch and its typed outcome; unresolved history is never inferred away.
class OnboardingAttempt {
  OnboardingAttempt({
    required this.number,
    required this.dispatchedAt,
    required this.outcome,
    this.rejection,
  }) {
    if (number < 1 ||
        number > 9007199254740991 ||
        !dispatchedAt.isUtc ||
        dispatchedAt.isBefore(DateTime.utc(1970))) {
      throw const FormatException('Invalid onboarding attempt.');
    }
    switch (outcome) {
      case OnboardingAttemptOutcome.rejected:
        if (rejection == null || !rejection!.establishesAttemptNonCommit) {
          throw const FormatException('Missing non-commit evidence.');
        }
      case OnboardingAttemptOutcome.conflict:
        if (rejection?.code != OnboardingBackendCode.idempotencyKeyConflict) {
          throw const FormatException('Missing key conflict evidence.');
        }
      case OnboardingAttemptOutcome.unresolved:
      case OnboardingAttemptOutcome.confirmed:
        if (rejection != null) {
          throw const FormatException('Unexpected rejection evidence.');
        }
    }
  }
  factory OnboardingAttempt.fromJson(Map<String, dynamic> json) {
    _recordShape(json, {'number', 'dispatchedAt', 'outcome'}, {'rejection'});
    if (json.containsKey('rejection') && json['rejection'] == null) {
      throw const FormatException('Invalid rejection evidence.');
    }
    return OnboardingAttempt(
      number: integer(json, 'number'),
      dispatchedAt: _dispatchTimestamp(text(json, 'dispatchedAt')),
      outcome: OnboardingAttemptOutcome.values.byName(text(json, 'outcome')),
      rejection: optionalObject(
        json['rejection'],
        OnboardingBackendRejection.fromJson,
      ),
    );
  }
  final int number;
  final DateTime dispatchedAt;
  final OnboardingAttemptOutcome outcome;
  final OnboardingBackendRejection? rejection;
  Map<String, dynamic> toJson() => {
    'number': number,
    'dispatchedAt': dispatchedAt.toIso8601String(),
    'outcome': outcome.name,
    if (rejection != null) 'rejection': rejection!.toJson(),
  };
}

/// One record per account/gym/API scope. It contains PII but never credentials.
class PendingOnboardingOperation {
  // Explicit legacy constructor. Restored v1 operations are never migrated.
  // New operations use create/prepared and the guarded version-2 service path.
  PendingOnboardingOperation({
    required OnboardingScope scope,
    required OnboardingRequest request,
    required String idempotencyKey,
    required DateTime createdAt,
    OnboardingResult? result,
  }) : this._(
         scope: scope,
         request: request,
         idempotencyKey: idempotencyKey,
         createdAt: createdAt,
         result: result,
       );

  PendingOnboardingOperation._({
    required this.scope,
    required this.request,
    required this.idempotencyKey,
    required this.createdAt,
    this.result,
    this.version = 1,
    this.revision = 0,
    List<OnboardingAttempt> attempts = const [],
    String? originalEncoding,
  }) : attempts = List.unmodifiable(attempts),
       _originalEncoding = originalEncoding {
    validateOnboardingKey(idempotencyKey);
    if (!createdAt.isUtc || createdAt.isBefore(DateTime.utc(1970))) {
      throw const FormatException('Invalid operation creation time.');
    }
    result?.validateFor(scope.gymId, request);
    if (version == 2) _validateLedger();
  }
  factory PendingOnboardingOperation.create({
    required OnboardingScope scope,
    required OnboardingRequest request,
  }) {
    final random = Random.secure();
    final key = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return PendingOnboardingOperation._(
      scope: scope,
      request: request,
      idempotencyKey: key,
      createdAt: DateTime.now().toUtc(),
      version: 2,
    );
  }

  /// Alias for new prepared version-2 operations. Generate once and retain it.
  factory PendingOnboardingOperation.prepared({
    required OnboardingScope scope,
    required OnboardingRequest request,
  }) {
    return PendingOnboardingOperation.create(scope: scope, request: request);
  }
  factory PendingOnboardingOperation.decode(String encoded) {
    try {
      final json = object(jsonDecode(encoded));
      final version = json['version'];
      if (version is! int) {
        throw const FormatException('Missing record version.');
      }
      if (version != 1 && version != 2) {
        throw const OnboardingFailure(OnboardingFailureKind.unsupportedVersion);
      }
      _recordShape(
        json,
        {
          'version',
          'scope',
          'requestJson',
          'idempotencyKey',
          'createdAt',
          'status',
          if (version == 2) ...{'revision', 'attempts'},
        },
        {'result'},
      );
      final scopeJson = object(json['scope']);
      _recordShape(scopeJson, {
        'environment',
        'apiBaseUrl',
        'userId',
        'gymId',
      }, {});
      final status = PendingOnboardingStatus.values.byName(
        text(json, 'status'),
      );
      if ((status == PendingOnboardingStatus.confirmed) !=
              (json['result'] != null) ||
          version == 1 &&
              status != PendingOnboardingStatus.pending &&
              status != PendingOnboardingStatus.confirmed) {
        throw const FormatException('Invalid pending status.');
      }
      final operation = PendingOnboardingOperation._(
        scope: OnboardingScope.fromJson(scopeJson),
        request: OnboardingRequest.fromFrozenJson(text(json, 'requestJson')),
        idempotencyKey: text(json, 'idempotencyKey'),
        createdAt: version == 2
            ? _dispatchTimestamp(text(json, 'createdAt'))
            : DateTime.parse(text(json, 'createdAt')),
        result: optionalObject(json['result'], OnboardingResult.fromJson),
        version: version,
        revision: version == 2 ? integer(json, 'revision') : 0,
        attempts: version == 2
            ? items(json['attempts'], OnboardingAttempt.fromJson)
            : const [],
        originalEncoding: encoded,
      );
      if (operation.status != status) {
        throw const FormatException(
          'Status does not match the attempt ledger.',
        );
      }
      return operation;
    } on OnboardingFailure {
      rethrow;
    } catch (_) {
      throw const OnboardingFailure(OnboardingFailureKind.corruptRecord);
    }
  }
  final OnboardingScope scope;
  final OnboardingRequest request;
  final String idempotencyKey;
  final DateTime createdAt;
  final OnboardingResult? result;
  final int version, revision;
  final List<OnboardingAttempt> attempts;
  final String? _originalEncoding;

  void _validateLedger() {
    if (attempts.isEmpty) {
      if (revision != 0 || result != null) {
        throw const FormatException('Invalid prepared operation.');
      }
      return;
    }
    var minimumRevision = attempts.length;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      if (attempt.number != index + 1) {
        throw const FormatException('Invalid attempt sequence.');
      }
      if (attempt.outcome != OnboardingAttemptOutcome.unresolved) {
        minimumRevision++;
      }
      if ((attempt.outcome == OnboardingAttemptOutcome.confirmed ||
              attempt.outcome == OnboardingAttemptOutcome.conflict) &&
          index != attempts.length - 1) {
        throw const FormatException('Attempt follows a terminal outcome.');
      }
    }
    if (revision < minimumRevision ||
        (attempts.last.outcome == OnboardingAttemptOutcome.confirmed) !=
            (result != null)) {
      throw const FormatException('Invalid ledger revision or confirmation.');
    }
  }

  PendingOnboardingStatus get status {
    if (result != null) return PendingOnboardingStatus.confirmed;
    if (version == 1) return PendingOnboardingStatus.pending;
    if (attempts.isEmpty) return PendingOnboardingStatus.prepared;
    if (attempts.last.outcome == OnboardingAttemptOutcome.conflict) {
      return PendingOnboardingStatus.reconciliationRequired;
    }
    if (attempts.any(
      (attempt) => attempt.outcome == OnboardingAttemptOutcome.unresolved,
    )) {
      return PendingOnboardingStatus.uncertain;
    }
    return PendingOnboardingStatus.rejected;
  }

  bool sameSubmission(PendingOnboardingOperation other) =>
      version == other.version &&
      scope.matches(other.scope) &&
      idempotencyKey == other.idempotencyKey &&
      request.frozenJson == other.request.frozenJson &&
      createdAt == other.createdAt;

  /// Immutable schema update. The store enforces revision and transition guards.
  /// Preserve serialized identity fields rather than normalizing restored values.
  PendingOnboardingOperation withLedger({
    required int revision,
    required List<OnboardingAttempt> attempts,
    OnboardingResult? result,
  }) {
    if (version != 2) {
      throw const OnboardingFailure(OnboardingFailureKind.unsupportedVersion);
    }
    final updated = PendingOnboardingOperation._(
      scope: scope,
      request: request,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      version: 2,
      revision: revision,
      attempts: attempts,
      result: result,
    );
    final json = object(jsonDecode(encode()));
    json['revision'] = revision;
    json['attempts'] = attempts.map((attempt) => attempt.toJson()).toList();
    json['status'] = updated.status.name;
    if (result == null) {
      json.remove('result');
    } else {
      json['result'] = result.toJson();
    }
    return PendingOnboardingOperation.decode(jsonEncode(json));
  }

  PendingOnboardingOperation confirmed(OnboardingResult result) {
    // The legacy confirmation path cannot invent evidence or reset a v2 ledger.
    if (version != 1) {
      throw const OnboardingFailure(OnboardingFailureKind.unsupportedVersion);
    }
    if (_originalEncoding != null) {
      final original = object(jsonDecode(_originalEncoding));
      original['status'] = 'confirmed';
      original['result'] = result.toJson();
      return PendingOnboardingOperation.decode(jsonEncode(original));
    }
    return PendingOnboardingOperation(
      scope: scope,
      request: request,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      result: result,
    );
  }

  String encode() =>
      _originalEncoding ??
      jsonEncode({
        'version': version,
        'scope': scope.toJson(),
        'requestJson': request.frozenJson,
        'idempotencyKey': idempotencyKey,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        if (version == 2) 'revision': revision,
        if (version == 2)
          'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
        if (result != null) 'result': result!.toJson(),
      });
}
