import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuthApi api;
  late FakeCredentialStorage storage;
  late AuthRepository repository;
  setUp(() {
    api = FakeAuthApi();
    storage = FakeCredentialStorage();
    repository = AuthRepository(api: api, storage: storage);
  });
  tearDown(() => repository.dispose());
  Future<void> login() => repository.login(
    email: 'person@example.invalid',
    password: syntheticCredential(),
  );
  Matcher kind(AuthFailureKind value) => throwsA(
    isA<AuthFailure>().having((failure) => failure.kind, 'kind', value),
  );

  test(
    'login publishes identity and persists only the refresh credential',
    () async {
      expect(repository.state, isA<SessionInitial>());
      await login();
      expect(repository.state, isA<SessionAuthenticated>());
      expect(storage.value == api.loginTokens.refreshToken, isTrue);
      expect(storage.value == api.loginTokens.accessToken, isFalse);
      expect(repository.accessToken == api.loginTokens.accessToken, isTrue);
      expect(storage.writes, 1);
    },
  );
  test('invalid credentials produce a typed session error', () async {
    api.loginFailure = const AuthFailure(AuthFailureKind.invalidCredentials);
    await expectLater(login(), kind(AuthFailureKind.invalidCredentials));
    expect(repository.state, isA<SessionError>());
    expect(storage.value, isNull);
    expect(repository.accessToken, isNull);
  });
  test(
    'restoration rotates persisted credentials and fetches current identity',
    () async {
      storage.value = syntheticCredential();
      await repository.restoreSession();
      expect(api.refreshCalls, 1);
      expect(api.meCalls, 1);
      expect(repository.state, isA<SessionAuthenticated>());
      expect(storage.value == api.rotatedTokens.refreshToken, isTrue);
    },
  );
  test(
    'missing stored credentials produces unauthenticated without API calls',
    () async {
      await repository.restoreSession();
      expect(repository.state, isA<SessionUnauthenticated>());
      expect(api.refreshCalls, 0);
      expect(api.meCalls, 0);
    },
  );
  test('logout clears credentials and bearer immediately', () async {
    await login();
    final pending = repository.logout();
    expect(repository.accessToken, isNull);
    await pending;
    expect(storage.value, isNull);
    expect(repository.state, isA<SessionUnauthenticated>());
    expect(
      api.loggedOutCredentials.single == api.loginTokens.refreshToken,
      isTrue,
    );
  });
  test(
    'logout still clears local credentials if backend revocation fails',
    () async {
      await login();
      api.logoutFailure = const AuthFailure(AuthFailureKind.network);
      await expectLater(repository.logout(), kind(AuthFailureKind.network));
      expect(storage.value, isNull);
      expect(repository.accessToken, isNull);
      expect(repository.state, isA<SessionError>());
    },
  );
  test(
    'refresh replaces both tokens and persists rotated credential',
    () async {
      await login();
      await repository.refreshSession();
      expect(storage.value == api.rotatedTokens.refreshToken, isTrue);
      expect(repository.accessToken == api.rotatedTokens.accessToken, isTrue);
      expect(storage.writes, 2);
    },
  );
  for (final value in [
    AuthFailureKind.invalidSession,
    AuthFailureKind.network,
    AuthFailureKind.server,
  ]) {
    test(
      'failed refresh (${value.name}) clears credentials and session',
      () async {
        await login();
        api.refreshFailure = AuthFailure(value);
        await expectLater(repository.refreshSession(), kind(value));
        expect(repository.accessToken, isNull);
        expect(storage.value, isNull);
        expect(repository.state, isA<SessionError>());
      },
    );
  }
  test('concurrent refresh callers share one actual API operation', () async {
    await login();
    api.refreshGate = Completer<void>();
    final first = repository.refreshSession();
    final second = repository.refreshSession();
    expect(identical(first, second), isTrue);
    await api.refreshEntered.future;
    expect(api.refreshCalls, 1);
    api.refreshGate!.complete();
    await Future.wait([first, second]);
    expect(api.refreshCalls, 1);
    expect(storage.writes, 2);
  });
  test(
    'concurrent restoration and refresh share credential rotation',
    () async {
      storage.value = syntheticCredential();
      api.refreshGate = Completer<void>();
      final first = repository.restoreSession();
      final second = repository.refreshSession();
      await api.refreshEntered.future;
      api.refreshGate!.complete();
      await Future.wait([first, second]);
      expect(api.refreshCalls, 1);
    },
  );
  test(
    'storage write failure never publishes an authenticated session',
    () async {
      storage.failWrite = true;
      await expectLater(login(), kind(AuthFailureKind.storage));
      expect(repository.accessToken, isNull);
      expect(storage.value, isNull);
      expect(repository.state, isA<SessionError>());
    },
  );
  test('storage read failure is surfaced safely', () async {
    storage.failRead = true;
    await expectLater(
      repository.restoreSession(),
      kind(AuthFailureKind.storage),
    );
    expect(repository.state, isA<SessionError>());
    expect(api.refreshCalls, 0);
  });
  test(
    'failed storage deletion blocks restoration of an untrusted credential',
    () async {
      await login();
      storage.failClear = true;
      await expectLater(repository.logout(), kind(AuthFailureKind.storage));
      expect(repository.accessToken, isNull);
      final previousRefreshCalls = api.refreshCalls;
      await expectLater(
        repository.restoreSession(),
        kind(AuthFailureKind.storage),
      );
      expect(api.refreshCalls, previousRefreshCalls);
    },
  );
  test('failed rotation persistence clears old credentials', () async {
    await login();
    storage.failWrite = true;
    await expectLater(
      repository.refreshSession(),
      kind(AuthFailureKind.storage),
    );
    expect(storage.value, isNull);
    expect(repository.accessToken, isNull);
  });
  test('me failure after rotation clears newly saved credentials', () async {
    storage.value = syntheticCredential();
    api.meFailure = const AuthFailure(AuthFailureKind.invalidSession);
    await expectLater(
      repository.restoreSession(),
      kind(AuthFailureKind.invalidSession),
    );
    expect(storage.value, isNull);
    expect(repository.accessToken, isNull);
  });
  test(
    'logout during refresh cannot resurrect a session and revokes latest credential',
    () async {
      await login();
      api.refreshGate = Completer<void>();
      final refresh = repository.refreshSession();
      final expectedFailure = expectLater(
        refresh,
        kind(AuthFailureKind.invalidSession),
      );
      await api.refreshEntered.future;
      final logout = repository.logout();
      expect(repository.accessToken, isNull);
      api.refreshGate!.complete();
      await expectedFailure;
      await logout;
      expect(repository.state, isA<SessionUnauthenticated>());
      expect(storage.value, isNull);
      expect(
        api.loggedOutCredentials.single == api.rotatedTokens.refreshToken,
        isTrue,
      );
    },
  );
}
