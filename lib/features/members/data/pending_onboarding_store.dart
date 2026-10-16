import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/pending_onboarding.dart';
import '../models/onboarding_models.dart';
import 'onboarding_failure.dart';

/// Container-owned queues survive provider replacement. Storage and submission
/// use separate queues, so a queued network operation can safely await storage.
class OnboardingOperationQueue {
  Future<void> _tail = Future.value();
  final _dispatches = <String, OnboardingDispatch>{};
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// A live, single-use permission to dispatch, issued only after durable read-back.
/// Restoring a record cannot issue this handle or close an earlier attempt.
class OnboardingDispatch {
  OnboardingDispatch._(this.operation, this._owner);
  final PendingOnboardingOperation operation;
  final OnboardingOperationQueue _owner;
  int get attemptNumber => operation.attempts.last.number;
}

abstract interface class PendingOnboardingStore {
  Future<PendingOnboardingOperation?> read(OnboardingScope scope);
  Future<PendingOnboardingOperation> save(PendingOnboardingOperation operation);
  Future<void> confirm(
    PendingOnboardingOperation operation,
    OnboardingResult result, {
    void Function()? beforePersist,
  });
  Future<void> acknowledge(
    PendingOnboardingOperation operation, {
    void Function()? beforePersist,
  });
  Future<OnboardingDispatch> markDispatched(
    PendingOnboardingOperation expected, {
    required int attemptNumber,
    required DateTime dispatchedAt,
    void Function()? beforePersist,
  });
  Future<PendingOnboardingOperation> recordAttemptOutcome(
    OnboardingDispatch dispatch, {
    required int attemptNumber,
    required OnboardingAttemptOutcome outcome,
    OnboardingBackendRejection? rejection,
    OnboardingResult? result,
    void Function()? beforePersist,
  });
  Future<PendingOnboardingOperation> replaceRejected(
    PendingOnboardingOperation expected,
    PendingOnboardingOperation replacement, {
    required int attemptNumber,
    void Function()? beforePersist,
  });
  Future<void> abandonDispatch(OnboardingDispatch dispatch);
}

/// The injected storage must provide verified persistence on write AND read.
/// Production uses OnboardingSecureStorage; ordinary FlutterSecureStorage is
/// insufficient. Injectable storage keeps the transition tests platform-free.
class SecurePendingOnboardingStore implements PendingOnboardingStore {
  SecurePendingOnboardingStore({
    required FlutterSecureStorage storage,
    required OnboardingOperationQueue queue,
  }) : _storage = storage,
       _queue = queue;
  final FlutterSecureStorage _storage;
  final OnboardingOperationQueue _queue;

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool uncertain = false,
  }) async {
    try {
      return await action();
    } on OnboardingFailure {
      rethrow;
    } catch (_) {
      throw OnboardingFailure(
        OnboardingFailureKind.localStorage,
        uncertain: uncertain,
      );
    }
  }

  /// A write exception is ambiguous. The production adapter's read requires a
  /// native persistence barrier, including after a failed commit; cached equality
  /// alone is never proof. Do not roll back/delete. Dispatch remains withheld
  /// after a write exception even if the verification barrier later succeeds.
  Future<PendingOnboardingOperation> _writeVerified(
    PendingOnboardingOperation next, {
    bool dispatch = false,
  }) async {
    var writeFailed = false;
    try {
      await _storage.write(key: next.scope.storageKey, value: next.encode());
    } catch (_) {
      writeFailed = true;
    }
    final actual = await _read(next.scope);
    if (actual == null ||
        actual.encode() != next.encode() ||
        writeFailed && dispatch) {
      throw const OnboardingFailure(
        OnboardingFailureKind.localStorage,
        uncertain: true,
      );
    }
    return actual;
  }

  Future<PendingOnboardingOperation> _expected(
    PendingOnboardingOperation expected,
  ) async {
    final actual = await _read(expected.scope);
    if (actual == null ||
        actual.version != 2 ||
        !actual.sameSubmission(expected) ||
        actual.revision != expected.revision) {
      throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
    }
    return actual;
  }

  Future<PendingOnboardingOperation?> _read(OnboardingScope scope) async {
    final value = await _storage.read(key: scope.storageKey);
    if (value == null) return null;
    final operation = PendingOnboardingOperation.decode(value);
    if (!scope.matches(operation.scope)) {
      throw const OnboardingFailure(OnboardingFailureKind.scopeMismatch);
    }
    return operation;
  }

  @override
  Future<PendingOnboardingOperation?> read(OnboardingScope scope) =>
      _queue.run(() => _guard(() => _read(scope)));

  @override
  Future<PendingOnboardingOperation> save(
    PendingOnboardingOperation operation,
  ) => _queue.run(
    () => _guard(() async {
      final existing = await _read(operation.scope);
      if (existing != null) {
        if (!existing.sameSubmission(operation)) {
          throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
        }
        // Never replace confirmed metadata with an older pending snapshot.
        return existing;
      }
      if (operation.result != null ||
          operation.version == 2 &&
              operation.status != PendingOnboardingStatus.prepared) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      return _writeVerified(operation);
    }),
  );

  @override
  Future<void> confirm(
    PendingOnboardingOperation operation,
    OnboardingResult result, {
    void Function()? beforePersist,
  }) => _queue.run(
    () => _guard(() async {
      final existing = await _read(operation.scope);
      if (existing == null ||
          !existing.sameSubmission(operation) ||
          existing.result != null &&
              existing.result!.operationId != result.operationId) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      result.validateFor(operation.scope.gymId, operation.request);
      beforePersist?.call();
      await _writeVerified(existing.confirmed(result));
    }),
  );

  /// Only a confirmed operation can be acknowledged. No timeout/logout cleanup,
  /// readAll/deleteAll, or automatic disposal cleanup is provided.
  /// Revalidate the caller's scope after storage I/O, immediately before issuing
  /// deletion. There is no await between this guard and the delete invocation;
  /// an already issued native deletion cannot be cancelled by this API.
  @override
  Future<void> acknowledge(
    PendingOnboardingOperation operation, {
    void Function()? beforePersist,
  }) => _queue.run(
    () => _guard(() async {
      final existing = await _read(operation.scope);
      if (existing == null) return;
      if (!existing.sameSubmission(operation) ||
          existing.result == null ||
          existing.version == 2 &&
              (existing.revision != operation.revision ||
                  existing.attempts.last.number !=
                      operation.attempts.lastOrNull?.number)) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      beforePersist?.call();
      await _storage.delete(key: operation.scope.storageKey);
    }),
  );

  /// The snapshot supplies the expected revision; the stored ledger supplies all
  /// history. A retry appends a marker, never resolves an earlier unknown attempt.
  @override
  Future<OnboardingDispatch> markDispatched(
    PendingOnboardingOperation expected, {
    required int attemptNumber,
    required DateTime dispatchedAt,
    void Function()? beforePersist,
  }) => _queue.run(
    () => _guard(() async {
      final actual = await _expected(expected);
      if (actual.result != null ||
          actual.status == PendingOnboardingStatus.reconciliationRequired ||
          _queue._dispatches.containsKey(actual.scope.storageKey) ||
          attemptNumber != actual.attempts.length + 1) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      final OnboardingAttempt attempt;
      try {
        attempt = OnboardingAttempt(
          number: attemptNumber,
          dispatchedAt: dispatchedAt,
          outcome: OnboardingAttemptOutcome.unresolved,
        );
      } on FormatException {
        throw const OnboardingFailure(OnboardingFailureKind.validation);
      }
      beforePersist?.call();
      final saved = await _writeVerified(
        actual.withLedger(
          revision: actual.revision + 1,
          attempts: [...actual.attempts, attempt],
        ),
        dispatch: true,
      );
      final handle = OnboardingDispatch._(saved, _queue);
      _queue._dispatches[actual.scope.storageKey] = handle;
      return handle;
    }, uncertain: true),
  );

  /// Only the live dispatch can provide its outcome. Consume it before storage
  /// access: a failed write/read cannot turn a later callback into new evidence.
  @override
  Future<PendingOnboardingOperation> recordAttemptOutcome(
    OnboardingDispatch dispatch, {
    required int attemptNumber,
    required OnboardingAttemptOutcome outcome,
    OnboardingBackendRejection? rejection,
    OnboardingResult? result,
    void Function()? beforePersist,
  }) => _queue.run(
    () => _guard(() async {
      final expected = dispatch.operation;
      if (!identical(dispatch._owner, _queue) ||
          !identical(_queue._dispatches[expected.scope.storageKey], dispatch) ||
          attemptNumber != dispatch.attemptNumber) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      final OnboardingAttempt completed;
      try {
        if ((outcome == OnboardingAttemptOutcome.confirmed) !=
            (result != null)) {
          throw const FormatException('Missing or unexpected result.');
        }
        result?.validateFor(expected.scope.gymId, expected.request);
        completed = OnboardingAttempt(
          number: attemptNumber,
          dispatchedAt: expected.attempts.last.dispatchedAt,
          outcome: outcome,
          rejection: rejection,
        );
      } on FormatException {
        throw const OnboardingFailure(OnboardingFailureKind.validation);
      }
      _queue._dispatches.remove(expected.scope.storageKey);
      final actual = await _expected(expected);
      if (actual.result != null ||
          actual.attempts.last.number != attemptNumber ||
          actual.attempts.last.outcome != OnboardingAttemptOutcome.unresolved) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      beforePersist?.call();
      return _writeVerified(
        actual.withLedger(
          revision: actual.revision + 1,
          attempts: [
            ...actual.attempts.take(actual.attempts.length - 1),
            completed,
          ],
          result: result,
        ),
      );
    }, uncertain: true),
  );

  /// Replace in the same slot only after every durable attempt proves non-commit.
  /// Legacy, uncertain, conflicted and confirmed operations are never released.
  @override
  Future<PendingOnboardingOperation> replaceRejected(
    PendingOnboardingOperation expected,
    PendingOnboardingOperation replacement, {
    required int attemptNumber,
    void Function()? beforePersist,
  }) => _queue.run(
    () => _guard(() async {
      final actual = await _expected(expected);
      if (!actual.scope.matches(replacement.scope)) {
        throw const OnboardingFailure(OnboardingFailureKind.scopeMismatch);
      }
      if (actual.status != PendingOnboardingStatus.rejected ||
          actual.result != null ||
          actual.attempts.isEmpty ||
          actual.attempts.last.number != attemptNumber ||
          _queue._dispatches.containsKey(actual.scope.storageKey) ||
          !actual.attempts.every(
            (attempt) =>
                attempt.outcome == OnboardingAttemptOutcome.rejected &&
                attempt.rejection?.establishesAttemptNonCommit == true,
          ) ||
          replacement.version != 2 ||
          replacement.revision != 0 ||
          replacement.attempts.isNotEmpty ||
          replacement.result != null ||
          replacement.idempotencyKey == actual.idempotencyKey) {
        throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
      }
      beforePersist?.call();
      return _writeVerified(replacement);
    }, uncertain: true),
  );

  /// Retire only this live permission; keep its durable unresolved marker intact.
  /// This is safe after cancellation/scope loss and creates no non-commit evidence.
  @override
  Future<void> abandonDispatch(OnboardingDispatch dispatch) =>
      _queue.run(() async {
        final key = dispatch.operation.scope.storageKey;
        if (identical(dispatch._owner, _queue) &&
            identical(_queue._dispatches[key], dispatch)) {
          _queue._dispatches.remove(key);
        }
      });
}
