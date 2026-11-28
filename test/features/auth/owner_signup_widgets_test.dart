import 'dart:typed_data';
import 'package:gym_management_app/features/owner_profile/owner_signup_photo.dart';
import '../members/photo_test_support.dart' show photoBytes;
import 'package:gym_management_app/shared/widgets/ambient_motion.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/auth/data/owner_registration_repository.dart';
import 'package:gym_management_app/features/auth/data/owner_registration_failure.dart';
import 'package:gym_management_app/features/auth/models/owner_registration.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/auth/providers/owner_registration_providers.dart';
import 'package:gym_management_app/features/auth/presentation/owner_signup_page.dart';
import 'auth_fakes.dart';

class FailingPhotoHandoff extends OwnerSignupPhotoStore {
  @override
  Future<void> recover() async {}
  @override
  Future<Uint8List?> preview() async => photoBytes;
  @override
  Future<void> confirmRegistration(String email) async =>
      throw StateError('local photo storage unavailable');
}

class FakeRegistration implements OwnerRegistrationRepository {
  int calls = 0;
  OwnerRegistrationRequest? request;
  Completer<void>? gate;
  OwnerRegistrationFailure? failure;
  @override
  Future<void> register(OwnerRegistrationRequest input) async {
    calls++;
    request = input;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
  }
}

Finder field(String name) => find.byKey(ValueKey(name));
TextField renderedField(WidgetTester tester, String name) =>
    tester.widget<TextField>(
      find.descendant(of: field(name), matching: find.byType(TextField)),
    );
Future<void> enter(WidgetTester tester, {String? password}) async {
  final privatePassword = password ?? syntheticCredential();
  for (final item in {
    'ownerFullName': 'Alex River',
    'email': 'owner@example.invalid',
    'password': privatePassword,
    'confirmPassword': privatePassword,
    'gymName': 'Example Gym',
  }.entries) {
    await tester.enterText(field(item.key), item.value);
  }
  final adultConfirmation = find.byKey(
    const ValueKey('adultAccountConfirmation'),
  );
  if (!tester.widget<CheckboxListTile>(adultConfirmation).value!) {
    await tester.ensureVisible(adultConfirmation);
    await tester.tap(adultConfirmation);
  }
  await tester.pump();
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
}

Future<ProviderContainer> pump(
  WidgetTester tester,
  FakeRegistration repository, {
  FakeAuthApi? api,
  FakeCredentialStorage? storage,
  bool signup = true,
  OwnerSignupPhotoStore? photos,
}) async {
  final container = ProviderContainer(
    overrides: [
      ownerRegistrationRepositoryProvider.overrideWithValue(repository),
      if (photos != null)
        ownerSignupPhotoStoreProvider.overrideWithValue(photos),
      authApiServiceProvider.overrideWithValue(api ?? FakeAuthApi()),
      credentialStorageProvider.overrideWithValue(
        storage ?? FakeCredentialStorage(),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const GymApp(animateDecorations: false),
    ),
  );
  await tester.pumpAndSettle();
  if (signup) {
    container.read(appRouterProvider).go(AppRoutes.signup);
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  testWidgets(
    'adult account declaration is required without submitting registration',
    (tester) async {
      final repository = FakeRegistration();
      await pump(tester, repository);
      await enter(tester);
      final confirmation = find.byKey(
        const ValueKey('adultAccountConfirmation'),
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await submit(tester);
      expect(repository.calls, 0);
      expect(
        find.text(
          'Confirm that you are at least 18 to create an owner account.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'optional photo handoff failure preserves confirmed account success without resubmitting',
    (tester) async {
      final repository = FakeRegistration();
      final container = await pump(
        tester,
        repository,
        photos: FailingPhotoHandoff(),
      );
      await enter(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(container.read(appRouterProvider).state.uri.path, AppRoutes.login);
      expect(
        find.text(
          'Account created. The optional photo could not be prepared. Add it from Edit owner profile after signing in.',
        ),
        findsOneWidget,
      );
      expect(
        container.read(sessionControllerProvider),
        isNot(isA<SessionAuthenticated>()),
      );
    },
  );

  testWidgets('Login Sign Up link opens public form before authentication', (
    tester,
  ) async {
    final container = await pump(tester, FakeRegistration(), signup: false);
    // Signed out, the app opens on phone sign-in; email sign-up is behind it.
    await tester.ensureVisible(find.text('Sign in with email and password'));
    await tester.tap(find.text('Sign in with email and password'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.signup,
    );
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(
      container.read(sessionControllerProvider),
      isA<SessionUnauthenticated>(),
    );
  });
  testWidgets(
    'required fields show specific messages without network submission',
    (tester) async {
      final repository = FakeRegistration();
      await pump(tester, repository);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter your full name (1–120 characters).'),
        findsOneWidget,
      );
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter a password.'), findsOneWidget);
      expect(find.text('Confirm your password.'), findsOneWidget);
      expect(
        find.text('Enter a gym name with 2–120 characters.'),
        findsOneWidget,
      );
      expect(repository.calls, 0);
    },
  );
  testWidgets(
    'email and mismatched confirmation fail at their fields; a simple password is fine',
    (tester) async {
      final repository = FakeRegistration();
      await pump(tester, repository);
      await enter(tester, password: 'password1234567890');
      await tester.enterText(field('email'), 'invalid');
      await tester.enterText(field('confirmPassword'), syntheticCredential());
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter a password.'), findsNothing);
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(repository.calls, 0);
    },
  );
  testWidgets(
    'both password visibility controls preserve text and have accessible labels',
    (tester) async {
      await pump(tester, FakeRegistration());
      final password = syntheticCredential();
      await enter(tester, password: password);
      for (final entry in {
        'password': 'Password',
        'confirmPassword': 'Confirm password',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.tap(find.byTooltip('Show ${entry.value}'));
        await tester.pump();
        final form = renderedField(tester, entry.key);
        expect(form.obscureText, false);
        expect(form.controller!.text == password, true);
        await tester.tap(find.byTooltip('Hide ${entry.value}'));
        await tester.pump();
        expect(renderedField(tester, entry.key).obscureText, true);
      }
    },
  );
  testWidgets('duplicate taps dispatch once and disable fields while loading', (
    tester,
  ) async {
    final repository = FakeRegistration()..gate = Completer<void>();
    await pump(tester, repository);
    await enter(tester);
    await submit(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(repository.calls, 1);
    expect(find.text('Creating account…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(renderedField(tester, 'password').enabled, false);
    repository.gate!.complete();
    await tester.pumpAndSettle();
  });
  for (final kind in [
    OwnerRegistrationFailureKind.duplicateEmail,
    OwnerRegistrationFailureKind.duplicateGym,
    OwnerRegistrationFailureKind.validation,
    OwnerRegistrationFailureKind.network,
    OwnerRegistrationFailureKind.rateLimited,
  ]) {
    testWidgets(
      '$kind preserves entered values and reports understandable errors without authenticating',
      (tester) async {
        final failure = OwnerRegistrationFailure(kind);
        final repository = FakeRegistration()..failure = failure;
        final container = await pump(tester, repository);
        final password = syntheticCredential();
        await enter(tester, password: password);
        await submit(tester);
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsWidgets);
        expect(
          renderedField(tester, 'password').controller!.text == password,
          true,
        );
        expect(
          renderedField(tester, 'ownerFullName').controller!.text,
          'Alex River',
        );
        expect(
          container.read(sessionControllerProvider),
          isA<SessionUnauthenticated>(),
        );
        if (kind == OwnerRegistrationFailureKind.duplicateEmail) {
          expect(
            renderedField(tester, 'email').decoration!.errorText,
            failure.message,
          );
        }
        if (kind == OwnerRegistrationFailureKind.duplicateGym) {
          expect(
            renderedField(tester, 'gymName').decoration!.errorText,
            failure.message,
          );
        }
        expect(repository.calls, 1);
      },
    );
  }
  testWidgets(
    'success returns to existing Login with notice and no auth credentials',
    (tester) async {
      final api = FakeAuthApi();
      final storage = FakeCredentialStorage();
      final repository = FakeRegistration();
      final container = await pump(
        tester,
        repository,
        api: api,
        storage: storage,
      );
      await enter(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.login,
      );
      expect(
        find.text('Account and gym created. Sign in to continue.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(api.loginCalls, 0);
      expect(storage.writes, 0);
      expect(
        container.read(sessionControllerProvider),
        isA<SessionUnauthenticated>(),
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text
            .isEmpty,
        true,
      );
    },
  );
  testWidgets('authenticated user cannot enter anonymous registration', (
    tester,
  ) async {
    final storage = FakeCredentialStorage()..value = syntheticCredential();
    final container = await pump(tester, FakeRegistration(), storage: storage);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(find.byType(OwnerSignupPage), findsNothing);
  });
  testWidgets(
    'narrow phone, open keyboard and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerRegistrationRepositoryProvider.overrideWithValue(
              FakeRegistration(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AmbientMotionSettings(
              enabled: false,
              child: OwnerSignupPage(),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('gymContactPhone'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Create account').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
