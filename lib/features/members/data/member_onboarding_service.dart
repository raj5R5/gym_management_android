import 'package:dio/dio.dart';
import '../models/onboarding_models.dart';
import '../models/pending_onboarding.dart';
import 'member_onboarding_repository.dart';
import 'onboarding_failure.dart';
import 'pending_onboarding_store.dart';

/// Data/session boundary only: no UI state, routing, automatic retry or auth logic.
class MemberOnboardingService {
  MemberOnboardingService({
    required MemberOnboardingRepository repository,
    required PendingOnboardingStore store,
    required OnboardingOperationQueue queue,
    required bool Function(OnboardingScope) isAuthorized,
  }) : _repository = repository,
       _store = store,
       _queue = queue,
       _isAuthorized = isAuthorized;
  final MemberOnboardingRepository _repository;
  final PendingOnboardingStore _store;
  final OnboardingOperationQueue _queue;
  final bool Function(OnboardingScope) _isAuthorized;
  CancelToken? _activeRequest;
  OnboardingScope? _activeScope;
  bool _disposed = false;

  void _check(OnboardingScope scope) {
    if (_disposed ||
        _activeRequest?.isCancelled == true ||
        !_isAuthorized(scope)) {
      throw const OnboardingFailure(OnboardingFailureKind.scopeMismatch);
    }
  }

  /// Called synchronously on authorization/scope changes. Cancellation does not
  /// imply rollback; the saved operation is retained for the original actor.
  void authorizationChanged() {
    if (_activeScope != null && !_isAuthorized(_activeScope!)) {
      _activeRequest?.cancel();
    }
  }

  void dispose() {
    _disposed = true;
    _activeRequest?.cancel();
  }

  Future<T> _run<T>(OnboardingScope scope, Future<T> Function() action) =>
      _queue.run(() async {
        _check(scope);
        _activeScope = scope;
        _activeRequest = CancelToken();
        try {
          return await action();
        } finally {
          _activeRequest = null;
          _activeScope = null;
        }
      });

  Future<PendingOnboardingOperation?> restore(OnboardingScope scope) =>
      _run(scope, () async {
        _check(scope);
        final operation = await _store.read(scope);
        _check(
          scope,
        ); // Never return PII after an account/gym change during storage I/O.
        return operation;
      });

  Future<OnboardingResult> submit(PendingOnboardingOperation operation) => _run(
    operation.scope,
    () async {
      _check(operation.scope);
      // Legacy submissions are allowed only when the exact record is already
      // durable. Newly created operations must use schema version 2.
      if (operation.version == 1) {
        final legacy = await _store.read(operation.scope);
        _check(operation.scope);
        if (legacy == null || !legacy.sameSubmission(operation)) {
          throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
        }
        return _send(legacy);
      }
      final saved = await _store.save(
        operation,
      ); // Fail closed BEFORE any network write.
      _check(operation.scope);
      return _send(saved);
    },
  );

  /// Recovery reads the durable frozen record, never accepts a replacement body/key.
  Future<OnboardingResult> recover(OnboardingScope scope) =>
      _run(scope, () async {
        _check(scope);
        final saved = await _store.read(scope);
        _check(scope);
        if (saved == null) {
          throw const OnboardingFailure(OnboardingFailureKind.pendingOperation);
        }
        return _send(saved);
      });

  Future<OnboardingResult> _send(PendingOnboardingOperation operation) async {
    _check(operation.scope);
    if (operation.result != null) return operation.result!;
    if (operation.version == 1) return _sendLegacy(operation);
    final dispatch = await _store.markDispatched(
      operation,
      attemptNumber: operation.attempts.length + 1,
      dispatchedAt: DateTime.now().toUtc(),
      beforePersist: () => _check(operation.scope),
    );
    try {
      _check(operation.scope);
      final OnboardingResult result;
      try {
        result = await _repository.complete(
          operation.scope.gymId,
          operation.request,
          operation.idempotencyKey,
          cancelToken: _activeRequest,
        );
        result.validateFor(operation.scope.gymId, operation.request);
      } catch (error) {
        final failure = error is OnboardingFailure
            ? error
            : const OnboardingFailure(
                OnboardingFailureKind.unexpectedResponse,
                uncertain: true,
              );
        _check(operation.scope);
        final evidence = failure.backendRejection;
        final outcome = _attemptOutcome(failure);
        final PendingOnboardingOperation saved;
        try {
          saved = await _persistOutcome(
            dispatch,
            outcome,
            rejection: outcome == OnboardingAttemptOutcome.unresolved
                ? null
                : evidence,
          );
        } on OnboardingFailure catch (persistenceFailure) {
          // Keep the storage/scope failure authoritative. HTTP diagnostics are
          // ephemeral context, never a substitute for durable rejection evidence.
          throw OnboardingFailure(
            persistenceFailure.kind,
            uncertain: persistenceFailure.uncertain,
            backendRejection: persistenceFailure.backendRejection,
            diagnostics: failure.diagnostics ?? persistenceFailure.diagnostics,
          );
        }
        _check(operation.scope);
        if (saved.result != null) return saved.result!;
        // Report uncertainty of the complete operation, not just this retry.
        throw OnboardingFailure(
          failure.kind,
          uncertain:
              saved.status == PendingOnboardingStatus.uncertain ||
              saved.status == PendingOnboardingStatus.reconciliationRequired,
          backendRejection: evidence,
          diagnostics: failure.diagnostics,
        );
      }
      _check(operation.scope);
      final confirmed = await _persistOutcome(
        dispatch,
        OnboardingAttemptOutcome.confirmed,
        result: result,
      );
      _check(operation.scope);
      return confirmed.result!;
    } finally {
      // Scope loss or disposal may prevent an outcome write. Do not leak the
      // live handle or resolve its durable marker merely to permit recovery.
      await _store.abandonDispatch(dispatch);
    }
  }

  OnboardingAttemptOutcome _attemptOutcome(OnboardingFailure failure) {
    final evidence = failure.backendRejection;
    if (evidence?.code == OnboardingBackendCode.idempotencyKeyConflict) {
      return OnboardingAttemptOutcome.conflict;
    }
    // Generic categories, uncertain errors and inconsistent causes prove nothing.
    if (evidence == null ||
        failure.uncertain ||
        failure.kind != evidence.code.kind ||
        !evidence.establishesAttemptNonCommit) {
      return OnboardingAttemptOutcome.unresolved;
    }
    return OnboardingAttemptOutcome.rejected;
  }

  Future<PendingOnboardingOperation> _persistOutcome(
    OnboardingDispatch dispatch,
    OnboardingAttemptOutcome outcome, {
    OnboardingBackendRejection? rejection,
    OnboardingResult? result,
  }) async {
    final operation = dispatch.operation;
    _check(operation.scope);
    try {
      return await _store.recordAttemptOutcome(
        dispatch,
        attemptNumber: dispatch.attemptNumber,
        outcome: outcome,
        rejection: rejection,
        result: result,
        beforePersist: () => _check(operation.scope),
      );
    } on OnboardingFailure catch (failure) {
      _check(operation.scope);
      // The store also verifies write-then-throw. If a caller still receives a
      // failure, trust only matching durable confirmation, never assume rollback.
      try {
        final actual = await _store.read(operation.scope);
        _check(operation.scope);
        if (actual != null &&
            actual.sameSubmission(operation) &&
            actual.result != null &&
            (result == null ||
                actual.result!.operationId == result.operationId)) {
          actual.result!.validateFor(operation.scope.gymId, operation.request);
          return actual;
        }
      } on OnboardingFailure catch (readFailure) {
        if (readFailure.kind == OnboardingFailureKind.scopeMismatch) rethrow;
      }
      throw OnboardingFailure(failure.kind, uncertain: true);
    }
  }

  /// Prepare the replacement once with create/prepared and reuse that same
  /// object/key if storage fails. Correction persists only; submit dispatches it.
  /// If verification fails, restore first: replacement may already be durable.
  Future<PendingOnboardingOperation> correct(
    PendingOnboardingOperation expected,
    PendingOnboardingOperation replacement,
  ) => _run(expected.scope, () async {
    _check(expected.scope);
    _check(replacement.scope);
    final saved = await _store.replaceRejected(
      expected,
      replacement,
      attemptNumber: expected.attempts.lastOrNull?.number ?? 0,
      beforePersist: () {
        _check(expected.scope);
        _check(replacement.scope);
      },
    );
    _check(saved.scope);
    return saved;
  });

  Future<OnboardingResult> _sendLegacy(
    PendingOnboardingOperation operation,
  ) async {
    _check(operation.scope);
    final result = await _repository.complete(
      operation.scope.gymId,
      operation.request,
      operation.idempotencyKey,
      cancelToken: _activeRequest,
    );
    _check(operation.scope);
    try {
      result.validateFor(operation.scope.gymId, operation.request);
    } on FormatException {
      throw const OnboardingFailure(
        OnboardingFailureKind.unexpectedResponse,
        uncertain: true,
      );
    }
    // Persist confirmation before exposing success. If this write fails, the
    // original record remains recoverable using the exact same endpoint/key.
    try {
      await _store.confirm(
        operation,
        result,
        beforePersist: () => _check(operation.scope),
      );
    } on OnboardingFailure catch (failure) {
      throw OnboardingFailure(failure.kind, uncertain: true);
    }
    _check(operation.scope);
    return result;
  }

  Future<void> acknowledge(PendingOnboardingOperation operation) =>
      _run(operation.scope, () async {
        _check(operation.scope);
        await _store.acknowledge(
          operation,
          beforePersist: () => _check(operation.scope),
        );
      });
}
