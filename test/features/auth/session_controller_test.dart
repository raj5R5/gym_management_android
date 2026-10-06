import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import 'auth_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeAuthApi api;
  late FakeCredentialStorage storage;
  setUp(() {
    api = FakeAuthApi();
    storage = FakeCredentialStorage();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(storage),
      ],
    );
  });
  tearDown(() => container.dispose());
  test(
    'controller starts idle; login and logout publish explicit states',
    () async {
      final states = <SessionState>[];
      container.listen(
        sessionControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      final controller = container.read(sessionControllerProvider.notifier);
      expect(container.read(sessionControllerProvider), isA<SessionInitial>());
      expect(api.loginCalls, 0);
      expect(api.refreshCalls, 0);
      await controller.login(
        email: 'person@example.invalid',
        password: syntheticCredential(),
      );
      expect(
        states.whereType<SessionLoading>().single.operation,
        SessionOperation.login,
      );
      expect(
        container.read(sessionControllerProvider),
        isA<SessionAuthenticated>(),
      );
      await controller.logout();
      expect(
        container.read(sessionControllerProvider),
        isA<SessionUnauthenticated>(),
      );
    },
  );
  test('restoration publishes restoring then authenticated', () async {
    storage.value = syntheticCredential();
    final states = <SessionState>[];
    container.listen(sessionControllerProvider, (_, next) => states.add(next));
    await container.read(sessionControllerProvider.notifier).restoreSession();
    expect(
      states.whereType<SessionLoading>().single.operation,
      SessionOperation.restoring,
    );
    expect(
      container.read(sessionControllerProvider),
      isA<SessionAuthenticated>(),
    );
  });
  test(
    'repository refresh failure reaches controller as a safe error',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login(
        email: 'person@example.invalid',
        password: syntheticCredential(),
      );
      api.refreshFailure = const AuthFailure(AuthFailureKind.invalidSession);
      await expectLater(
        controller.refreshSession(),
        throwsA(isA<AuthFailure>()),
      );
      expect(container.read(sessionControllerProvider), isA<SessionError>());
      expect(container.read(authRepositoryProvider).accessToken, isNull);
    },
  );
}
