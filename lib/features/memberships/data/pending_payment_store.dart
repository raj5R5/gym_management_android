import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/config/app_config.dart';
import '../../members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../../members/models/pending_onboarding.dart' show OnboardingScope;
import '../../members/models/member_models.dart';
import '../models/billing_models.dart';
import 'billing_failure.dart';
import 'payment_repository.dart';

class PaymentRecoveryScope {
  PaymentRecoveryScope(this.account, this.memberId, this.subscriptionId) {
    for (final id in [memberId, subscriptionId]) {
      if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
        throw const FormatException('Invalid payment scope.');
      }
    }
  }
  factory PaymentRecoveryScope.fromConfig(
    AppConfig config, {
    required String userId,
    required String gymId,
    required String memberId,
    required String subscriptionId,
  }) => PaymentRecoveryScope(
    OnboardingScope.fromConfig(config, userId: userId, gymId: gymId),
    memberId,
    subscriptionId,
  );
  final OnboardingScope account;
  final String memberId, subscriptionId;
  String get storageKey =>
      'gym.payment.v1.${account.environment.name}.'
      '${Uri.encodeComponent(account.apiBaseUrl)}.${Uri.encodeComponent(account.userId)}.'
      '${account.gymId.toLowerCase()}.${memberId.toLowerCase()}.${subscriptionId.toLowerCase()}.pending';
  bool matches(PaymentRecoveryScope other) =>
      account.matches(other.account) &&
      memberId == other.memberId &&
      subscriptionId == other.subscriptionId;
  Map<String, dynamic> toJson() => {
    ...account.toJson(),
    'memberId': memberId,
    'subscriptionId': subscriptionId,
  };
  factory PaymentRecoveryScope.fromJson(Map<String, dynamic> json) =>
      PaymentRecoveryScope(
        OnboardingScope.fromJson(json),
        text(json, 'memberId'),
        text(json, 'subscriptionId'),
      );
}

enum PaymentAttemptOutcome { unresolved, rejected, conflict, confirmed }

class PaymentAttempt {
  PaymentAttempt(this.outcome, {this.code, this.httpStatus}) {
    if (outcome == PaymentAttemptOutcome.rejected) {
      if (code == null ||
          !paymentRejections.containsKey(code) ||
          paymentRejections[code] != httpStatus) {
        throw const FormatException('Invalid payment rejection evidence.');
      }
    } else if (outcome == PaymentAttemptOutcome.conflict) {
      if (code != 'IDEMPOTENCY_KEY_CONFLICT' ||
          (httpStatus != null && (httpStatus! < 100 || httpStatus! > 599))) {
        throw const FormatException('Invalid payment conflict evidence.');
      }
    } else if (code != null || httpStatus != null) {
      throw const FormatException('Unexpected payment evidence.');
    }
  }
  final PaymentAttemptOutcome outcome;
  final String? code;
  final int? httpStatus;
  Map<String, dynamic> toJson() => {
    'outcome': outcome.name,
    if (code != null) 'code': code,
    if (httpStatus != null) 'httpStatus': httpStatus,
  };
  factory PaymentAttempt.fromJson(Map<String, dynamic> json) {
    _shape(json, {'outcome'}, {'code', 'httpStatus'});
    return PaymentAttempt(
      PaymentAttemptOutcome.values.byName(text(json, 'outcome')),
      code: json.containsKey('code') ? text(json, 'code') : null,
      httpStatus: json.containsKey('httpStatus')
          ? integer(json, 'httpStatus')
          : null,
    );
  }
}

void _shape(
  Map<String, dynamic> json,
  Set<String> required,
  Set<String> optional,
) {
  if (!json.keys.toSet().containsAll(required) ||
      json.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    throw const FormatException('Invalid payment recovery fields.');
  }
}

/// No credentials or member profile are persisted. Only the frozen request,
/// identity, attempt history and minimal immutable receipt required for recovery.
class PendingPayment {
  PendingPayment({
    required this.scope,
    required this.collection,
    required this.createdAt,
    this.revision = 0,
    List<PaymentAttempt> attempts = const [],
    this.result,
  }) : attempts = List.unmodifiable(attempts) {
    if (collection.memberId != scope.memberId ||
        collection.subscriptionId != scope.subscriptionId ||
        !createdAt.isUtc ||
        createdAt.isBefore(DateTime.utc(1970)) ||
        revision < 0 ||
        revision !=
            attempts.length +
                attempts
                    .where((a) => a.outcome != PaymentAttemptOutcome.unresolved)
                    .length ||
        (attempts.lastOrNull?.outcome == PaymentAttemptOutcome.confirmed) !=
            (result != null) ||
        attempts
            .take(attempts.isEmpty ? 0 : attempts.length - 1)
            .any(
              (a) =>
                  a.outcome == PaymentAttemptOutcome.confirmed ||
                  a.outcome == PaymentAttemptOutcome.conflict,
            )) {
      throw const FormatException('Inconsistent payment recovery record.');
    }
    collection.validateResultIfPresent(result, scope);
  }
  final PaymentRecoveryScope scope;
  final PaymentCollection collection;
  final DateTime createdAt;
  final int revision;
  final List<PaymentAttempt> attempts;
  final RecordedPayment? result;
  bool get conflict =>
      attempts.lastOrNull?.outcome == PaymentAttemptOutcome.conflict;
  bool get rejected =>
      result == null &&
      attempts.isNotEmpty &&
      attempts.every((a) => a.outcome == PaymentAttemptOutcome.rejected);
  bool get unresolved => result == null && !rejected;
  bool sameOperation(PendingPayment other) =>
      scope.matches(other.scope) &&
      collection.key == other.collection.key &&
      collection.frozenJson == other.collection.frozenJson &&
      createdAt == other.createdAt;
  PendingPayment advance(
    List<PaymentAttempt> attempts, {
    RecordedPayment? result,
  }) => PendingPayment(
    scope: scope,
    collection: collection,
    createdAt: createdAt,
    revision: revision + 1,
    attempts: attempts,
    result: result,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'scope': scope.toJson(),
    'requestJson': collection.frozenJson,
    'key': collection.key,
    'createdAt': createdAt.toIso8601String(),
    'revision': revision,
    'attempts': attempts.map((a) => a.toJson()).toList(),
    if (result != null) 'result': paymentReceiptJson(result!),
  };
  String encode() => jsonEncode(toJson());
  factory PendingPayment.decode(String encoded) {
    try {
      final json = object(jsonDecode(encoded));
      _shape(
        json,
        {
          'version',
          'scope',
          'requestJson',
          'key',
          'createdAt',
          'revision',
          'attempts',
        },
        {'result'},
      );
      if (json['version'] != 1) {
        throw const FormatException('Unsupported payment recovery version.');
      }
      final scope = object(json['scope']);
      _shape(scope, {
        'environment',
        'apiBaseUrl',
        'userId',
        'gymId',
        'memberId',
        'subscriptionId',
      }, {});
      if (json.containsKey('result')) {
        _shape(
          object(json['result']),
          {
            'id',
            'gymId',
            'memberId',
            'subscriptionId',
            'amountPaise',
            'status',
            'paymentMethod',
            'paidAt',
          },
          {'transactionReference', 'recordedByUserId'},
        );
      }
      final createdAt = DateTime.parse(text(json, 'createdAt'));
      if (!createdAt.isUtc ||
          createdAt.toIso8601String() != text(json, 'createdAt')) {
        throw const FormatException('Invalid payment creation timestamp.');
      }
      return PendingPayment(
        scope: PaymentRecoveryScope.fromJson(scope),
        collection: PaymentCollection.fromFrozenJson(
          text(json, 'requestJson'),
          text(json, 'key'),
        ),
        createdAt: DateTime.parse(text(json, 'createdAt')),
        revision: integer(json, 'revision'),
        attempts: items(json['attempts'], PaymentAttempt.fromJson),
        result: optionalObject(json['result'], RecordedPayment.fromJson),
      );
    } catch (_) {
      throw const BillingFailure(
        'The saved payment cannot be read by this app. It has been kept; do not record it again.',
        uncertain: true,
      );
    }
  }
}

extension on PaymentCollection {
  void validateResultIfPresent(
    RecordedPayment? result,
    PaymentRecoveryScope scope,
  ) {
    if (result != null) {
      validateResult(result, scope.account.gymId, userId: scope.account.userId);
    }
  }
}

Map<String, dynamic> paymentReceiptJson(RecordedPayment result) => {
  'id': result.id,
  'gymId': result.gymId,
  'memberId': result.memberId,
  'subscriptionId': result.subscriptionId,
  'amountPaise': result.amountPaise,
  'status': result.status,
  'paymentMethod': result.method.wireValue,
  'paidAt': result.paidAt.toIso8601String(),
  'transactionReference': result.reference,
  'recordedByUserId': result.recordedByUserId,
};

class PendingPaymentStore {
  PendingPaymentStore({
    required FlutterSecureStorage storage,
    required OnboardingOperationQueue queue,
  }) : _storage = storage,
       _queue = queue;
  final FlutterSecureStorage _storage;
  final OnboardingOperationQueue _queue;
  Future<T> _run<T>(Future<T> Function() action) => _queue.run(() async {
    try {
      return await action();
    } on BillingFailure {
      rethrow;
    } catch (_) {
      throw const BillingFailure(
        'Saved payment storage could not be verified. No new payment is allowed until recovery succeeds.',
        uncertain: true,
      );
    }
  });
  Future<PendingPayment?> _read(PaymentRecoveryScope scope) async {
    final encoded = await _storage.read(key: scope.storageKey);
    if (encoded == null) return null;
    final actual = PendingPayment.decode(encoded);
    if (!actual.scope.matches(scope)) {
      throw const BillingFailure(
        'This saved payment belongs to another account or membership.',
        uncertain: true,
      );
    }
    return actual;
  }

  Future<PendingPayment?> read(PaymentRecoveryScope scope) =>
      _run(() => _read(scope));
  Future<PendingPayment> _expected(PendingPayment expected) async {
    final actual = await _read(expected.scope);
    if (actual == null ||
        !actual.sameOperation(expected) ||
        actual.revision != expected.revision) {
      throw const BillingFailure(
        'The saved payment changed. Recheck it before another action.',
        uncertain: true,
      );
    }
    return actual;
  }

  Future<PendingPayment> _write(PendingPayment next) async {
    // A failed native acknowledgement cannot authorize network dispatch.
    // Production reads also use the native durability barrier, never cache alone.
    await _storage.write(key: next.scope.storageKey, value: next.encode());
    final actual = await _read(next.scope);
    if (actual == null || actual.encode() != next.encode()) {
      throw const BillingFailure(
        'The payment has not been submitted. Saving its recovery details could not be verified.',
        uncertain: true,
      );
    }
    return actual;
  }

  Future<PendingPayment> prepare(
    PendingPayment next, {
    PendingPayment? replacing,
    required void Function() guard,
  }) => _run(() async {
    final actual = await _read(next.scope);
    if (actual != null) {
      if (actual.sameOperation(next)) {
        guard();
        return actual;
      }
      if (replacing == null ||
          !actual.sameOperation(replacing) ||
          actual.revision != replacing.revision ||
          !actual.rejected ||
          actual.collection.key == next.collection.key) {
        throw const BillingFailure(
          'Resolve the saved payment before recording another.',
          uncertain: true,
        );
      }
    } else if (replacing != null) {
      throw const BillingFailure(
        'The rejected payment could not be verified.',
        uncertain: true,
      );
    }
    if (next.revision != 0 || next.attempts.isNotEmpty || next.result != null) {
      throw const FormatException('Only prepared payments may be saved.');
    }
    guard();
    return _write(next);
  });
  Future<PendingPayment> dispatch(
    PendingPayment expected, {
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.result != null || actual.conflict || actual.rejected) {
      throw const BillingFailure(
        'This saved payment cannot be dispatched.',
        uncertain: true,
      );
    }
    guard();
    return _write(
      actual.advance([
        ...actual.attempts,
        PaymentAttempt(PaymentAttemptOutcome.unresolved),
      ]),
    );
  });
  Future<PendingPayment> outcome(
    PendingPayment expected,
    PaymentAttempt attempt, {
    RecordedPayment? result,
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.attempts.lastOrNull?.outcome !=
            PaymentAttemptOutcome.unresolved ||
        attempt.outcome == PaymentAttemptOutcome.unresolved) {
      throw const FormatException('Invalid payment outcome transition.');
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
    PendingPayment expected, {
    required void Function() guard,
  }) => _run(() async {
    final actual = await _expected(expected);
    if (actual.result == null) {
      throw const BillingFailure(
        'Only a confirmed payment may be cleared.',
        uncertain: true,
      );
    }
    guard();
    await _storage.delete(key: actual.scope.storageKey);
    if (await _read(actual.scope) != null) {
      throw const BillingFailure(
        'The saved confirmation could not be cleared. Review it again.',
        uncertain: true,
      );
    }
  });
}
