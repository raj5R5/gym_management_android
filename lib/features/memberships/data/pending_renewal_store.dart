import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../../members/models/member_models.dart';
import '../models/renewal_operation.dart';
import 'billing_failure.dart';
import 'pending_payment_store.dart' show PaymentRecoveryScope;

// Exact documented rejections only. An earlier unresolved attempt still blocks
// replacement even when a subsequent attempt receives one of these responses.
const renewalRejections = <String, int>{
  'ACTIVE_MEMBERSHIP_EXISTS': 409,
  'VALIDATION_ERROR': 400,
  'INVALID_AUTHENTICATION': 401,
  'FORBIDDEN': 403,
  'MEMBER_NOT_FOUND': 404,
  'SUBSCRIPTION_NOT_FOUND': 404,
  'PLAN_NOT_FOUND': 404,
  'RENEWAL_PREVIEW_CHANGED': 409,
  'SUBSCRIPTION_OVERLAP': 409,
  'SUBSCRIPTION_CANCELLED': 409,
  'SUBSCRIPTION_ALREADY_RENEWED': 409,
  'PAYMENT_OVERPAYMENT': 409,
  'DUPLICATE_PAYMENT_REFERENCE': 409,
  'RATE_LIMITED': 429,
};

enum RenewalOutcome { unresolved, rejected, conflict, confirmed }

class RenewalAttempt {
  RenewalAttempt(this.outcome, {this.code, this.status}) {
    if (outcome == RenewalOutcome.rejected &&
            renewalRejections[code] != status ||
        outcome == RenewalOutcome.rejected && code == null ||
        outcome == RenewalOutcome.conflict &&
            (code != 'IDEMPOTENCY_KEY_CONFLICT' || status != 409) ||
        (outcome == RenewalOutcome.unresolved ||
                outcome == RenewalOutcome.confirmed) &&
            (code != null || status != null)) {
      throw const FormatException('Invalid renewal evidence.');
    }
  }
  final RenewalOutcome outcome;
  final String? code;
  final int? status;
  Map<String, dynamic> toJson() => {
    'outcome': outcome.name,
    if (code != null) 'code': code,
    if (status != null) 'status': status,
  };
  factory RenewalAttempt.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference({
      'outcome',
      'code',
      'status',
    }).isNotEmpty) {
      throw const FormatException('Unknown renewal evidence.');
    }
    return RenewalAttempt(
      RenewalOutcome.values.byName(text(json, 'outcome')),
      code: optionalText(json, 'code'),
      status: json['status'] == null ? null : integer(json, 'status'),
    );
  }
}

class PendingRenewal {
  PendingRenewal({
    required this.scope,
    required this.request,
    required this.createdAt,
    this.revision = 0,
    List<RenewalAttempt> attempts = const [],
    this.result,
  }) : attempts = List.unmodifiable(attempts) {
    if (!createdAt.isUtc ||
        createdAt.isBefore(DateTime.utc(1970)) ||
        revision !=
            attempts.length +
                attempts
                    .where((a) => a.outcome != RenewalOutcome.unresolved)
                    .length ||
        (attempts.lastOrNull?.outcome == RenewalOutcome.confirmed) !=
            (result != null) ||
        attempts
            .take(attempts.isEmpty ? 0 : attempts.length - 1)
            .any(
              (a) =>
                  a.outcome == RenewalOutcome.confirmed ||
                  a.outcome == RenewalOutcome.conflict,
            )) {
      throw const FormatException('Inconsistent renewal recovery record.');
    }
    if (result != null) {
      request.validateResult(
        result!,
        gymId: scope.account.gymId,
        memberId: scope.memberId,
        predecessorId: scope.subscriptionId,
      );
    }
  }
  final PaymentRecoveryScope scope;
  // Separate logical slot beneath the existing native-approved payment prefix.
  // Original installment/onboarding keys and encodings are never altered.
  String get storageKey =>
      scope.storageKey.replaceFirst(RegExp(r'\.pending$'), '.renewal.pending');
  final RenewalOperationRequest request;
  final DateTime createdAt;
  final int revision;
  final List<RenewalAttempt> attempts;
  final RenewalResult? result;
  bool get conflict => attempts.lastOrNull?.outcome == RenewalOutcome.conflict;
  bool get rejected =>
      result == null &&
      attempts.isNotEmpty &&
      attempts.every((a) => a.outcome == RenewalOutcome.rejected);
  bool same(PendingRenewal other) =>
      scope.matches(other.scope) &&
      request.key == other.request.key &&
      request.frozenJson == other.request.frozenJson &&
      createdAt == other.createdAt;
  PendingRenewal advance(
    List<RenewalAttempt> attempts, {
    RenewalResult? result,
  }) => PendingRenewal(
    scope: scope,
    request: request,
    createdAt: createdAt,
    revision: revision + 1,
    attempts: attempts,
    result: result,
  );
  String encode() => jsonEncode({
    'version': 1,
    'scope': scope.toJson(),
    'requestJson': request.frozenJson,
    'key': request.key,
    'createdAt': createdAt.toIso8601String(),
    'revision': revision,
    'attempts': attempts.map((a) => a.toJson()).toList(),
    if (result != null) 'result': result!.toJson(),
  });
  factory PendingRenewal.decode(String encoded) {
    final json = object(jsonDecode(encoded));
    if (json['version'] != 1 ||
        !json.keys.toSet().containsAll({
          'version',
          'scope',
          'requestJson',
          'key',
          'createdAt',
          'revision',
          'attempts',
        }) ||
        json.keys.toSet().difference({
          'version',
          'scope',
          'requestJson',
          'key',
          'createdAt',
          'revision',
          'attempts',
          'result',
        }).isNotEmpty) {
      throw const FormatException('Unsupported renewal record.');
    }
    final scopeJson = object(json['scope']);
    if (scopeJson.keys.toSet().difference({
      'environment',
      'apiBaseUrl',
      'userId',
      'gymId',
      'memberId',
      'subscriptionId',
    }).isNotEmpty) {
      throw const FormatException('Unknown renewal scope.');
    }
    final createdAt = DateTime.parse(text(json, 'createdAt'));
    if (createdAt.toIso8601String() != text(json, 'createdAt')) {
      throw const FormatException('Invalid renewal creation timestamp.');
    }
    return PendingRenewal(
      scope: PaymentRecoveryScope.fromJson(scopeJson),
      request: RenewalOperationRequest.frozen(
        text(json, 'requestJson'),
        text(json, 'key'),
      ),
      createdAt: DateTime.parse(text(json, 'createdAt')),
      revision: integer(json, 'revision'),
      attempts: items(json['attempts'], RenewalAttempt.fromJson),
      result: optionalObject(json['result'], RenewalResult.fromJson),
    );
  }
}

class PendingRenewalStore {
  PendingRenewalStore({
    required FlutterSecureStorage storage,
    required OnboardingOperationQueue queue,
  }) : _storage = storage,
       _queue = queue;
  final FlutterSecureStorage _storage;
  final OnboardingOperationQueue _queue;
  String _key(PaymentRecoveryScope scope) =>
      scope.storageKey.replaceFirst(RegExp(r'\.pending$'), '.renewal.pending');
  Future<T> _run<T>(Future<T> Function() work) => _queue.run(() async {
    try {
      return await work();
    } on BillingFailure {
      rethrow;
    } catch (_) {
      throw const BillingFailure(
        'Saved renewal could not be verified. Keep it for exact recovery; do not renew again.',
        uncertain: true,
      );
    }
  });
  Future<PendingRenewal?> _read(PaymentRecoveryScope scope) async {
    final value = await _storage.read(key: _key(scope));
    if (value == null) return null;
    final record = PendingRenewal.decode(value);
    if (!record.scope.matches(scope)) {
      throw const FormatException('Renewal scope mismatch.');
    }
    return record;
  }

  Future<PendingRenewal?> read(PaymentRecoveryScope scope) =>
      _run(() => _read(scope));
  Future<PendingRenewal> _expected(PendingRenewal expected) async {
    final actual = await _read(expected.scope);
    if (actual == null ||
        !actual.same(expected) ||
        actual.revision != expected.revision) {
      throw const BillingFailure(
        'Saved renewal changed. Recheck before another action.',
        uncertain: true,
      );
    }
    return actual;
  }

  Future<PendingRenewal> _write(PendingRenewal next) async {
    await _storage.write(key: next.storageKey, value: next.encode());
    final actual = await _read(next.scope);
    if (actual == null || actual.encode() != next.encode()) {
      throw const FormatException('Renewal persistence not verified.');
    }
    return actual;
  }

  Future<PendingRenewal> prepare(
    PendingRenewal next, {
    PendingRenewal? replacing,
    required void Function() guard,
  }) => _run(() async {
    final actual = await _read(next.scope);
    if (actual != null) {
      if (actual.same(next)) {
        guard();
        return actual;
      }
      if (replacing == null ||
          !actual.same(replacing) ||
          actual.revision != replacing.revision ||
          !actual.rejected ||
          actual.request.key == next.request.key) {
        throw const BillingFailure(
          'Resolve the saved renewal first.',
          uncertain: true,
        );
      }
    } else if (replacing != null) {
      throw const BillingFailure(
        'The rejected renewal could not be verified.',
        uncertain: true,
      );
    }
    if (next.revision != 0 || next.attempts.isNotEmpty || next.result != null) {
      throw const FormatException(
        'Only prepared renewal may replace rejection.',
      );
    }
    guard();
    return _write(next);
  });
  Future<PendingRenewal> dispatch(
    PendingRenewal expected, {
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.result != null || actual.conflict || actual.rejected) {
      throw const BillingFailure(
        'Saved renewal cannot be dispatched.',
        uncertain: true,
      );
    }
    guard();
    return _write(
      actual.advance([
        ...actual.attempts,
        RenewalAttempt(RenewalOutcome.unresolved),
      ]),
    );
  });
  Future<PendingRenewal> outcome(
    PendingRenewal expected,
    RenewalAttempt attempt, {
    RenewalResult? result,
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.attempts.lastOrNull?.outcome != RenewalOutcome.unresolved ||
        attempt.outcome == RenewalOutcome.unresolved) {
      throw const FormatException('Invalid renewal outcome.');
    }
    guard();
    return _write(
      actual.advance([
        ...actual.attempts.take(actual.attempts.length - 1),
        attempt,
      ], result: result),
    );
  });
  Future<void> acknowledge(
    PendingRenewal expected, {
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.result == null) {
      throw const BillingFailure(
        'Only confirmed renewal may be cleared.',
        uncertain: true,
      );
    }
    guard();
    await _storage.delete(key: actual.storageKey);
    if (await _read(actual.scope) != null) {
      throw const FormatException('Renewal acknowledgement not verified.');
    }
  });
}
