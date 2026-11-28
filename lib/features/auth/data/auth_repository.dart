import 'dart:async';

import '../../../core/storage/credential_storage.dart';
import '../models/auth_models.dart';
import '../models/session_state.dart';
import 'auth_api_service.dart';
import 'auth_diagnostics.dart';
import 'auth_failure.dart';
import 'auth_operation_queue.dart';

/// The sole session authority. Session mutations and credential writes are ordered.
class AuthRepository {
  AuthRepository({
    required AuthApiService api,
    required CredentialStorage storage,
    AuthOperationQueue? operationQueue,
    AuthDiagnostics diagnostics = const AuthDiagnostics(),
  }) : _api = api,
       _storage = storage,
       _queue = operationQueue ?? AuthOperationQueue(),
       _diagnostics = diagnostics;

  final AuthApiService _api;
  final CredentialStorage _storage;
  final AuthOperationQueue _queue;
  final AuthDiagnostics _diagnostics;
  final _changes = StreamController<SessionState>.broadcast(sync: true);
  SessionState _state = const SessionInitial();
  AuthTokens? _tokens;
  AuthTokens? _stagedTokens;
  Future<void>? _refreshFlight;
  int _revision = 0;
  bool _blocked = false;
  bool _storageUnsafe = false;
  bool _disposed = false;

  SessionState get state => _state;
  Stream<SessionState> get changes => _changes.stream;
  int get revision => _revision;
  Future<void>? get pendingRecovery => _refreshFlight;

  /// Infrastructure only; credentials are never included in SessionState.
  String? get accessToken =>
      _blocked || _disposed ? null : _tokens?.accessToken;

  void _emit(SessionState value) {
    if (_disposed) return;
    _state = value;
    _changes.add(value);
  }

  Future<T> _ordered<T>(Future<T> Function() action) {
    return _queue.run(() {
      _checkAlive();
      return action();
    });
  }

  void _checkAlive() {
    if (_disposed) throw const AuthFailure(AuthFailureKind.invalidSession);
  }

  void _checkRevision(int revision) {
    if (_disposed || revision != _revision) {
      throw const AuthFailure(AuthFailureKind.invalidSession);
    }
  }

  AuthFailure _failure(Object error) => switch (error) {
    AuthFailure failure => failure,
    CredentialStorageFailure() => const AuthFailure(AuthFailureKind.storage),
    _ => const AuthFailure(AuthFailureKind.unexpectedResponse),
  };

  Future<void> _clear() async {
    _checkAlive();
    _tokens = null;
    _stagedTokens = null;
    _blocked = true;
    try {
      _diagnostics.record(AuthStage.credentialClear, AuthEvent.started);
      await _storage.clearRefreshCredential();
      _checkAlive();
      _storageUnsafe = false;
      _diagnostics.record(AuthStage.credentialClear, AuthEvent.succeeded);
    } catch (_) {
      _checkAlive();
      _storageUnsafe = true;
      _diagnostics.record(
        AuthStage.credentialClear,
        AuthEvent.failed,
        failure: const AuthFailure(AuthFailureKind.storage),
      );
      throw const AuthFailure(AuthFailureKind.storage);
    }
  }

  Future<AuthFailure> _fail(Object error, int revision) async {
    _checkRevision(revision);
    var failure = _failure(error);
    try {
      await _clear();
    } on AuthFailure catch (clearFailure) {
      failure = clearFailure;
    }
    _checkRevision(revision);
    _emit(SessionError(failure));
    return failure;
  }

  Future<void> _stage(AuthTokens tokens, int revision) async {
    _checkAlive();
    // Keep the latest rotation for queued logout, even if logout superseded us.
    // It is never exposed as a usable access token until recovery commits.
    _stagedTokens = tokens;
    _checkRevision(revision);
    try {
      _diagnostics.record(AuthStage.credentialWrite, AuthEvent.started);
      await _storage.writeRefreshCredential(tokens.refreshToken);
      _checkRevision(revision);
      _diagnostics.record(AuthStage.credentialWrite, AuthEvent.succeeded);
    } catch (_) {
      _checkRevision(revision);
      _storageUnsafe = true;
      _diagnostics.record(
        AuthStage.credentialWrite,
        AuthEvent.failed,
        failure: const AuthFailure(AuthFailureKind.storage),
      );
      throw const AuthFailure(AuthFailureKind.storage);
    }
  }

  void _commit(AuthTokens tokens, AuthIdentity identity, int revision) {
    _checkRevision(revision);
    _tokens = tokens;
    _stagedTokens = null;
    _blocked = false;
    _emit(SessionAuthenticated(identity));
  }

  Future<void> login({required String email, required String password}) =>
      _signIn(() => _api.login(email: email, password: password));

  /// Signs in with credentials the server issued after checking a phone code.
  /// The phone check happens outside the session; only its result is stored here.
  Future<void> adopt(LoginResponse response) => _signIn(() async => response);

  Future<void> _signIn(Future<LoginResponse> Function() obtain) {
    final revision = ++_revision;
    _blocked = true;
    return _ordered(() async {
      _checkRevision(revision);
      _emit(const SessionLoading(SessionOperation.login));
      try {
        await _clear();
        _checkRevision(revision);
        final response = await obtain();
        await _stage(response.tokens, revision);
        _commit(response.tokens, response.identity, revision);
      } catch (error) {
        // Preserve the latest rotated credential for a queued logout to revoke.
        if (revision != _revision || _disposed) throw _failure(error);
        throw await _fail(error, revision);
      }
    });
  }

  Future<void> restoreSession() => _refresh(restoring: true);
  Future<void> refreshSession() => _refresh(restoring: false);

  Future<void> _refresh({required bool restoring}) {
    final existing = _refreshFlight;
    if (existing != null) return existing;
    final revision = _revision;
    late final Future<void> flight;
    flight =
        _ordered(() async {
          _checkRevision(revision);
          final operation = restoring ? AuthStage.restore : AuthStage.refresh;
          var stage = operation;
          final watch = Stopwatch()..start();
          _diagnostics.record(operation, AuthEvent.started);
          _blocked = true;
          _emit(
            SessionLoading(
              restoring
                  ? SessionOperation.restoring
                  : SessionOperation.refreshing,
            ),
          );
          try {
            if (_storageUnsafe) {
              throw const AuthFailure(AuthFailureKind.storage);
            }
            stage = AuthStage.credentialRead;
            _diagnostics.record(stage, AuthEvent.started);
            final credential =
                _stagedTokens?.refreshToken ??
                _tokens?.refreshToken ??
                await _storage.readRefreshCredential();
            _checkRevision(revision);
            _diagnostics.record(stage, AuthEvent.succeeded);
            if (credential == null) {
              _checkRevision(revision);
              _blocked = true;
              _emit(const SessionUnauthenticated());
              _diagnostics.record(operation, AuthEvent.absent);
              if (!restoring) {
                throw const AuthFailure(AuthFailureKind.invalidSession);
              }
              return;
            }
            if (!AuthTokens.validRefreshCredential(credential)) {
              throw const AuthFailure(AuthFailureKind.invalidSession);
            }
            _checkRevision(revision);
            stage = AuthStage.refreshApi;
            final tokens = await _api.refresh(credential);
            stage = AuthStage.credentialWrite;
            await _stage(tokens, revision);
            _checkRevision(revision);
            stage = AuthStage.currentUserApi;
            final identity = await _api.currentUser(tokens.accessToken);
            _checkRevision(revision);
            _commit(tokens, identity, revision);
            _diagnostics.record(
              operation,
              AuthEvent.succeeded,
              elapsedMs: watch.elapsedMilliseconds,
            );
          } catch (error) {
            if (revision != _revision || _disposed) {
              _diagnostics.record(operation, AuthEvent.superseded);
              throw _failure(error);
            }

            final failure = _failure(error);
            _diagnostics.record(
              stage,
              AuthEvent.failed,
              failure: failure,
              elapsedMs: watch.elapsedMilliseconds,
            );
            final preserveCredential =
                restoring &&
                (failure.kind == AuthFailureKind.network ||
                    failure.kind == AuthFailureKind.server ||
                    failure.kind == AuthFailureKind.rateLimited ||
                    (stage == AuthStage.credentialRead &&
                        failure.kind == AuthFailureKind.storage));

            if (preserveCredential) {
              _checkRevision(revision);
              _blocked = true;
              _diagnostics.record(
                operation,
                AuthEvent.preserved,
                failure: failure,
                elapsedMs: watch.elapsedMilliseconds,
              );
              _emit(SessionError(failure, canRetryRestoration: true));
              throw failure;
            }

            throw await _fail(error, revision);
          }
        }).whenComplete(() {
          if (identical(_refreshFlight, flight)) _refreshFlight = null;
        });
    _refreshFlight = flight;
    return flight;
  }

  Future<void> logout() {
    final revision = ++_revision;
    _blocked = true; // Stop bearer attachment immediately, even during refresh.
    _emit(const SessionUnauthenticated());
    return _ordered(() async {
      AuthFailure? failure;
      try {
        final credential =
            _stagedTokens?.refreshToken ??
            _tokens?.refreshToken ??
            await _storage.readRefreshCredential();
        _checkAlive();
        if (credential != null) await _api.logout(credential);
      } catch (error) {
        _checkAlive();
        failure = _failure(error);
      }
      _checkAlive();
      try {
        await _clear();
      } on AuthFailure catch (error) {
        failure = error;
      }
      if (revision == _revision) {
        _emit(
          failure == null
              ? const SessionUnauthenticated()
              : SessionError(failure),
        );
      }
      if (failure != null) throw failure;
    });
  }

  Future<void> invalidateSession() {
    final revision = ++_revision;
    _blocked = true;
    return _ordered(() async {
      final failure = await _fail(
        const AuthFailure(AuthFailureKind.invalidSession),
        revision,
      );
      if (failure.kind == AuthFailureKind.storage) throw failure;
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    _tokens = null;
    _stagedTokens = null;
    _changes.close();
  }
}
