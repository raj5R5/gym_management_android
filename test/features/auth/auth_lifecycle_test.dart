import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';

import 'auth_fakes.dart';

void main() {
  Future<void> login(AuthRepository repository) => repository.login(
    email: 'person@example.invalid',
    password: syntheticCredential(),
  );
  Matcher invalidSession() => throwsA(
    isA<AuthFailure>().having(
      (failure) => failure.kind,
      'kind',
      AuthFailureKind.invalidSession,
    ),
  );

  for (final phase in ['persistence', 'me']) {
    test('rotated session is unavailable while $phase is pending', () async {
      final api = FakeAuthApi();
      final storage = FakeCredentialStorage();
      final repository = AuthRepository(api: api, storage: storage);
      addTearDown(repository.dispose);
      await login(repository);
      final gate = Completer<void>();
      if (phase == 'persistence') {
        storage.writeGate = gate;
        storage.writeEntered = Completer<void>();
      } else {
        api.meGate = gate;
      }
      final recovery = repository.refreshSession();
      await (phase == 'persistence'
          ? storage.writeEntered!.future
          : api.meEntered.future);
      expect(repository.accessToken, isNull);
      expect(repository.state, isA<SessionLoading>());
      expect(identical(recovery, repository.refreshSession()), isTrue);
      gate.complete();
      await recovery;
      expect(repository.accessToken == api.rotatedTokens.accessToken, isTrue);
      expect(repository.state, isA<SessionAuthenticated>());
    });
  }

  for (final operation in ['login', 'refresh']) {
    test(
      'disposal during $operation prevents new writes and publication',
      () async {
        final api = FakeAuthApi();
        final storage = FakeCredentialStorage();
        final repository = AuthRepository(api: api, storage: storage);
        final states = <SessionState>[];
        final subscription = repository.changes.listen(states.add);
        addTearDown(subscription.cancel);
        final gate = Completer<void>();
        if (operation == 'refresh') {
          await login(repository);
          api.refreshGate = gate;
        } else {
          api.loginGate = gate;
        }
        final pending = operation == 'login'
            ? login(repository)
            : repository.refreshSession();
        final failed = expectLater(pending, invalidSession());
        await (operation == 'login'
            ? api.loginEntered.future
            : api.refreshEntered.future);
        final writes = storage.writes;
        final clears = storage.clears;
        final emissions = states.length;
        repository.dispose();
        gate.complete();
        await failed;
        expect(storage.writes, writes);
        expect(storage.clears, clears);
        expect(states.length, emissions);
        expect(repository.accessToken, isNull);
        expect(api.meCalls, 0);
      },
    );
  }

  for (final phase in ['persistence', 'me']) {
    test(
      'logout during $phase revokes staged rotation without publication',
      () async {
        final api = FakeAuthApi();
        final storage = FakeCredentialStorage();
        final repository = AuthRepository(api: api, storage: storage);
        addTearDown(repository.dispose);
        await login(repository);
        final gate = Completer<void>();
        if (phase == 'persistence') {
          storage.writeGate = gate;
          storage.writeEntered = Completer<void>();
        } else {
          api.meGate = gate;
        }
        final recovery = repository.refreshSession();
        final failed = expectLater(recovery, invalidSession());
        await (phase == 'persistence'
            ? storage.writeEntered!.future
            : api.meEntered.future);
        final logout = repository.logout();
        expect(repository.accessToken, isNull);
        gate.complete();
        await failed;
        await logout;
        expect(
          api.loggedOutCredentials.single == api.rotatedTokens.refreshToken,
          isTrue,
        );
        expect(storage.value, isNull);
        expect(repository.state, isA<SessionUnauthenticated>());
      },
    );
  }

  test(
    'queued operations after disposal perform no API or storage mutations',
    () async {
      final api = FakeAuthApi();
      final storage = FakeCredentialStorage();
      final repository = AuthRepository(api: api, storage: storage);
      repository.dispose();
      await expectLater(login(repository), invalidSession());
      await expectLater(repository.refreshSession(), invalidSession());
      await expectLater(repository.logout(), invalidSession());
      await expectLater(repository.invalidateSession(), invalidSession());
      expect(api.loginCalls, 0);
      expect(api.refreshCalls, 0);
      expect(storage.writes, 0);
      expect(storage.clears, 0);
    },
  );

  test('disposal during me does not initiate credential cleanup', () async {
    final api = FakeAuthApi()..meGate = Completer<void>();
    final storage = FakeCredentialStorage()..value = syntheticCredential();
    final repository = AuthRepository(api: api, storage: storage);
    final pending = repository.restoreSession();
    final failed = expectLater(pending, invalidSession());
    await api.meEntered.future;
    final clears = storage.clears;
    repository.dispose();
    api.meGate!.complete();
    await failed;
    expect(storage.clears, clears);
    expect(repository.accessToken, isNull);
    expect(repository.state, isNot(isA<SessionAuthenticated>()));
  });

  for (final phase in ['api', 'native write']) {
    test(
      'provider replacement waits for old $phase without stale overwrite',
      () async {
        final api = FakeAuthApi();
        final storage = FakeCredentialStorage();
        var activeApi = api;
        final replacementApi = FakeAuthApi();
        final container = ProviderContainer(
          overrides: [
            authApiServiceProvider.overrideWith((ref) => activeApi),
            credentialStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        final old = container.read(authRepositoryProvider);
        final gate = Completer<void>();
        if (phase == 'api') {
          api.loginGate = gate;
        } else {
          storage.writeGate = gate;
          storage.writeEntered = Completer<void>();
        }
        final pending = login(old);
        final failed = expectLater(pending, invalidSession());
        await (phase == 'api'
            ? api.loginEntered.future
            : storage.writeEntered!.future);
        activeApi = replacementApi;
        container.invalidate(authApiServiceProvider);
        final replacement = container.read(authRepositoryProvider);
        expect(identical(old, replacement), isFalse);
        final fresh = login(replacement);
        // The replacement must remain queued until the old operation drains.
        await Future<void>.delayed(Duration.zero);
        expect(api.loginCalls, 1);
        expect(replacementApi.loginCalls, 0);
        gate.complete();
        await failed;
        api.loginGate = null;
        storage.writeGate = null;
        await fresh;
        expect(storage.writes, phase == 'api' ? 1 : 2);
        expect(
          storage.value == replacementApi.loginTokens.refreshToken,
          isTrue,
        );
        expect(old.accessToken, isNull);
        expect(old.state, isNot(isA<SessionAuthenticated>()));
        expect(replacement.state, isA<SessionAuthenticated>());
        expect(
          replacement.accessToken == replacementApi.loginTokens.accessToken,
          isTrue,
        );
      },
    );
  }
}
