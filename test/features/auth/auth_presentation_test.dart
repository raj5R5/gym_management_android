import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import 'auth_fakes.dart';
import 'auth_widget_harness.dart';

void main() {
  testWidgets('login renders labelled email and obscured password fields', (
    tester,
  ) async {
    await pumpGym(tester);
    await tester.pumpAndSettle();
    expect(find.text('Gym Management'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
      isTrue,
    );
    expect(find.text('Login'), findsOneWidget);
  });

  for (final scenario in [
    (email: '', password: 'generated', message: 'Enter your email.'),
    (
      email: 'invalid',
      password: 'generated',
      message: 'Enter a valid email address.',
    ),
    (
      email: 'person@example.invalid',
      password: '',
      message: 'Enter your password.',
    ),
  ]) {
    testWidgets('validation: ${scenario.message}', (tester) async {
      final api = FakeAuthApi();
      await pumpGym(tester, api: api);
      await tester.pumpAndSettle();
      await enterLogin(
        tester,
        email: scenario.email,
        password: scenario.password.isEmpty ? '' : syntheticCredential(),
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text(scenario.message), findsOneWidget);
      expect(api.loginCalls, 0);
    });
  }

  testWidgets(
    'visibility toggle preserves password and has accessible labels',
    (tester) async {
      await pumpGym(tester);
      await tester.pumpAndSettle();
      final password = syntheticCredential();
      await enterLogin(tester, password: password);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse,
      );
      expect(
        tester
                .widget<TextField>(find.byType(TextField).at(1))
                .controller!
                .text ==
            password,
        isTrue,
      );
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
    },
  );

  testWidgets(
    'login trims email, preserves password, and state drives home on stable router',
    (tester) async {
      final api = FakeAuthApi();
      final container = await pumpGym(tester, api: api);
      await tester.pumpAndSettle();
      final router = container.read(appRouterProvider);
      final password = ' ${syntheticCredential()} ';
      await enterLogin(
        tester,
        email: ' person@example.invalid ',
        password: password,
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(api.loginCalls, 1);
      expect(api.submittedEmail, 'person@example.invalid');
      expect(api.submittedPassword == password, isTrue);
      expect(api.meCalls, 0);
      expect(find.text('You are signed in.'), findsOneWidget);
      expect(identical(router, container.read(appRouterProvider)), isTrue);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
    },
  );

  testWidgets(
    'pending login shows progress and prevents button and keyboard duplicates',
    (tester) async {
      final api = FakeAuthApi()..loginGate = Completer<void>();
      await pumpGym(tester, api: api);
      await tester.pumpAndSettle();
      await enterLogin(tester);
      await tester.tap(find.text('Login'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      tester.widget<TextField>(find.byType(TextField).at(1)).onSubmitted!('');
      await tester.pump();
      expect(api.loginCalls, 1);
      api.loginGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('You are signed in.'), findsOneWidget);
    },
  );

  for (final kind in [
    AuthFailureKind.invalidCredentials,
    AuthFailureKind.network,
    AuthFailureKind.server,
  ]) {
    testWidgets(
      'login displays only safe ${kind.name} error and allows retry',
      (tester) async {
        final api = FakeAuthApi()..loginFailure = AuthFailure(kind);
        await pumpGym(tester, api: api);
        await tester.pumpAndSettle();
        await enterLogin(tester);
        await tester.tap(find.text('Login'));
        await tester.pumpAndSettle();
        expect(find.text(AuthFailure(kind).message), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        expect(find.text('You are signed in.'), findsNothing);
      },
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'restoration holds startup without login flash then ${fails ? 'login' : 'home'}',
      (tester) async {
        final api = FakeAuthApi()..refreshGate = Completer<void>();
        if (fails) {
          api.refreshFailure = const AuthFailure(
            AuthFailureKind.invalidSession,
          );
        }
        final storage = FakeCredentialStorage()..value = syntheticCredential();
        final container = await pumpGym(tester, api: api, storage: storage);
        await tester.pump();
        expect(
          container.read(sessionControllerProvider),
          isA<SessionLoading>(),
        );
        expect(find.text('Restoring your session…'), findsOneWidget);
        expect(find.text('Login'), findsNothing);
        final router = container.read(appRouterProvider);
        router.go(AppRoutes.home);
        await tester.pump();
        await tester.pump();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.startup,
        );
        expect(find.text('You are signed in.'), findsNothing);
        api.refreshGate!.complete();
        await tester.pumpAndSettle();
        expect(api.refreshCalls, 1);
        expect(
          find.text(fails ? 'Sign in to your account' : 'You are signed in.'),
          findsOneWidget,
        );
        expect(
          storage.value == (fails ? null : api.rotatedTokens.refreshToken),
          isTrue,
        );
        expect(api.meCalls, fails ? 0 : 1);
      },
    );
  }

  testWidgets('me recovery must complete before home or login appears', (
    tester,
  ) async {
    final api = FakeAuthApi()..meGate = Completer<void>();
    await pumpGym(
      tester,
      api: api,
      storage: FakeCredentialStorage()..value = syntheticCredential(),
    );
    await tester.pump();
    expect(api.meCalls, 1);
    expect(find.text('Restoring your session…'), findsOneWidget);
    expect(find.text('Login'), findsNothing);
    expect(find.text('You are signed in.'), findsNothing);
    api.meGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('You are signed in.'), findsOneWidget);
  });

  testWidgets(
    'authenticated login redirects to home and unknown route recovers',
    (tester) async {
      final container = await pumpGym(
        tester,
        storage: FakeCredentialStorage()..value = syntheticCredential(),
      );
      await tester.pumpAndSettle();
      final router = container.read(appRouterProvider);
      router.go(AppRoutes.login);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
      router.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text('You are signed in.'), findsOneWidget);
      router.go('/missing-page');
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget);
      await tester.tap(find.text('Return to start'));
      await tester.pumpAndSettle();
      expect(find.text('You are signed in.'), findsOneWidget);
    },
  );

  for (final name in ['Alex', null, '   ']) {
    testWidgets(
      'home greets with display name or email (${name ?? 'absent'})',
      (tester) async {
        final api = FakeAuthApi()
          ..identity = AuthIdentity(
            user: AuthUser(
              id: 'test-account',
              email: 'person@example.invalid',
              status: AccountStatus.active,
              displayName: name,
            ),
            gymAccess: [],
          );
        await pumpGym(
          tester,
          api: api,
          storage: FakeCredentialStorage()..value = syntheticCredential(),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Welcome, ${name == 'Alex' ? 'Alex' : 'person@example.invalid'}',
          ),
          findsOneWidget,
        );
        expect(find.text('Logout'), findsOneWidget);
      },
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'logout shows progress, blocks duplicates, clears credentials (${fails ? 'backend fails' : 'success'})',
      (tester) async {
        final api = FakeAuthApi()..logoutGate = Completer<void>();
        if (fails) {
          api.logoutFailure = const AuthFailure(AuthFailureKind.network);
        }
        final storage = FakeCredentialStorage()..value = syntheticCredential();
        final container = await pumpGym(tester, api: api, storage: storage);
        await tester.pumpAndSettle();
        final router = container.read(appRouterProvider);
        await tester.tap(find.text('Logout'));
        await tester.pump();
        expect(find.text('Logging out…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(container.read(authRepositoryProvider).accessToken, isNull);
        final duplicate = container
            .read(sessionControllerProvider.notifier)
            .logout();
        final duplicateResult = fails
            ? expectLater(duplicate, throwsA(isA<AuthFailure>()))
            : expectLater(duplicate, completes);
        expect(api.loggedOutCredentials.length, 1);
        api.logoutGate!.complete();
        await duplicateResult;
        await tester.pumpAndSettle();
        expect(storage.value, isNull);
        expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
        expect(find.text('Sign in to your account'), findsOneWidget);
        expect(identical(router, container.read(appRouterProvider)), isTrue);
        expect(
          container.read(sessionControllerProvider),
          fails ? isA<SessionError>() : isA<SessionUnauthenticated>(),
        );
      },
    );
  }

  testWidgets('login remains usable on a small screen with keyboard space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGym(tester);
    await tester.pumpAndSettle();
    await enterLogin(tester);
    await tester.ensureVisible(find.text('Login'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('You are signed in.'), findsOneWidget);
  });
}
