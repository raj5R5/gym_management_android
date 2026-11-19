import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/config/public_app_info.dart';
import 'package:gym_management_app/core/platform/public_links.dart';
import 'package:gym_management_app/features/account_privacy/account_deletion_page.dart';
import 'package:gym_management_app/features/account_privacy/account_deletion_repository.dart';
import 'package:gym_management_app/features/account_privacy/privacy_support_page.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import '../auth/auth_fakes.dart';
import '../auth/auth_widget_harness.dart';

class FixedSession extends SessionController {
  @override
  SessionState build() => SessionAuthenticated(syntheticIdentity());
  void signOut() => state = const SessionUnauthenticated();
}

class RequestsFake implements AccountDeletionRepository {
  DeletionRequest? receipt;
  int writes = 0;
  Completer<void>? gate;
  bool uncertain = false;
  @override
  Future<DeletionRequest?> status(String userId, CancelToken cancel) async =>
      receipt;
  @override
  Future<DeletionRequest> request(
    String userId,
    String password,
    CancelToken cancel,
  ) async {
    writes++;
    if (gate != null) await gate!.future;
    receipt = DeletionRequest(
      id: 'a' * 24,
      userId: userId,
      status: 'requested',
      requestedAt: DateTime.utc(2026, 10, 23),
    );
    if (uncertain) {
      throw const AccountDeletionFailure(
        'The outcome is uncertain. Recheck status.',
      );
    }
    return receipt!;
  }
}

class FailedStatus extends RequestsFake {
  int reads = 0;
  @override
  Future<DeletionRequest?> status(String userId, CancelToken cancel) async {
    reads++;
    throw const AccountDeletionFailure(
      'The endpoint is not deployed. Retry after deployment.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'deletion status uses a read-only GET and verifies its receipt scope',
    () async {
      final client = Dio(
        BaseOptions(baseUrl: 'https://api.example.test/api/v1/'),
      );
      addTearDown(() => client.close(force: true));
      final repo = DioAccountDeletionRepository(client);
      for (final data in [
        null,
        {
          'id': 'a' * 24,
          'userId': 'test-account',
          'status': 'requested',
          'requestedAt': '2026-10-23T00:00:00Z',
        },
      ]) {
        client.httpClientAdapter = CallbackAdapter((request) {
          expect(request.method, 'GET');
          expect(request.path, 'auth/account-deletion-request');
          expect(request.data, isNull);
          return jsonResponse({
            'success': true,
            'data': {'request': data},
          });
        });
        final receipt = await repo.status('test-account', CancelToken());
        expect(receipt?.status, data == null ? isNull : 'requested');
      }
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': true,
          'data': {
            'request': {
              'id': 'a' * 24,
              'userId': 'another-account',
              'status': 'requested',
              'requestedAt': '2026-10-23T00:00:00Z',
            },
          },
        }),
      );
      await expectLater(
        repo.status('test-account', CancelToken()),
        throwsA(isA<AccountDeletionFailure>()),
      );
    },
  );

  test(
    'unavailable or unauthorized status cannot become a successful receipt',
    () async {
      final client = Dio(
        BaseOptions(baseUrl: 'https://api.example.test/api/v1/'),
      );
      addTearDown(() => client.close(force: true));
      final repo = DioAccountDeletionRepository(client);
      for (final failure in [
        (401, 'INVALID_AUTHENTICATION'),
        (404, 'NOT_FOUND'),
        (429, 'RATE_LIMITED'),
        (503, 'SERVICE_UNAVAILABLE'),
      ]) {
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': false,
            'error': {'code': failure.$2},
          }, status: failure.$1),
        );
        await expectLater(
          repo.status('test-account', CancelToken()),
          throwsA(isA<AccountDeletionFailure>()),
        );
      }
    },
  );

  test(
    'repository verifies identity and never accepts missing or false receipts',
    () async {
      final client = Dio(
        BaseOptions(baseUrl: 'https://api.example.test/api/v1/'),
      );
      addTearDown(() => client.close(force: true));
      final repo = DioAccountDeletionRepository(client);
      for (final request in [
        null,
        {
          'id': 'a' * 24,
          'userId': 'foreign',
          'status': 'requested',
          'requestedAt': '2026-10-23T00:00:00Z',
        },
      ]) {
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': true,
            'data': {'request': request},
          }),
        );
        await expectLater(
          repo.request('test-account', syntheticCredential(), CancelToken()),
          throwsA(isA<AccountDeletionFailure>()),
        );
      }
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, 'auth/account-deletion-request');
        expect(
          (request.data as Map).keys,
          unorderedEquals(['currentPassword', 'acknowledgement']),
        );
        return jsonResponse({
          'success': true,
          'data': {
            'request': {
              'id': 'a' * 24,
              'userId': 'test-account',
              'status': 'requested',
              'requestedAt': '2026-10-23T00:00:00Z',
            },
          },
        });
      });
      expect(
        (await repo.request(
          'test-account',
          syntheticCredential(),
          CancelToken(),
        )).status,
        'requested',
      );
    },
  );
  test(
    'public browser bridge sends HTTPS only and propagates browser errors',
    () async {
      const channel = MethodChannel('gym_management/public_links');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await const PublicLinks().open(
        Uri.parse('https://gym-company.com/privacy'),
      );
      expect(calls.single.method, 'openHttps');
      await expectLater(
        const PublicLinks().open(Uri.parse('http://gym-company.com/privacy')),
        throwsFormatException,
      );
      expect(calls.length, 1);
    },
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    RequestsFake requests, {
    bool dark = true,
    double scale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(FixedSession.new),
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        accountDeletionRepositoryProvider.overrideWithValue(requests),
        publicAppInfoProvider.overrideWithValue(const PublicAppInfo()),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const AccountDeletionPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'request requires acknowledgement/password, disables while busy and confirms a receipt',
    (tester) async {
      final requests = RequestsFake()..gate = Completer<void>();
      await pump(tester, requests);
      var button = find.widgetWithText(FilledButton, 'Submit deletion request');
      // Icon buttons use a FilledButton subclass; test the real button type.
      button = find.ancestor(
        of: find.text('Submit deletion request'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), syntheticCredential());
      await tester.ensureVisible(find.text('Submit deletion request'));
      await tester.tap(find.text('Submit deletion request'));
      await tester.pump();
      expect(find.text('Sending request…'), findsOneWidget);
      expect(requests.writes, 1);
      requests.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Request received'), findsOneWidget);
      expect(
        find.text(
          'Your request was saved. Account deletion has not been confirmed.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unavailable status waits for explicit retry without background polling',
    (tester) async {
      final requests = FailedStatus();
      await pump(tester, requests);
      await tester.pump(const Duration(seconds: 30));
      expect(requests.reads, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(requests.reads, 2);
    },
  );
  testWidgets(
    'uncertain POST rechecks authoritative status rather than making a second write',
    (tester) async {
      final requests = RequestsFake()..uncertain = true;
      await pump(tester, requests);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(find.byType(TextFormField), syntheticCredential());
      await tester.ensureVisible(find.text('Submit deletion request'));
      await tester.tap(find.text('Submit deletion request'));
      await tester.pumpAndSettle();
      expect(requests.writes, 1);
      expect(find.text('Request received'), findsOneWidget);
    },
  );
  testWidgets(
    'a late request cannot display another signed-out account receipt',
    (tester) async {
      final requests = RequestsFake()..gate = Completer<void>();
      final container = await pump(tester, requests);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(find.byType(TextFormField), syntheticCredential());
      await tester.ensureVisible(find.text('Submit deletion request'));
      await tester.tap(find.text('Submit deletion request'));
      await tester.pump();
      (container.read(sessionControllerProvider.notifier) as FixedSession)
          .signOut();
      await tester.pump();
      requests.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Request received'), findsNothing);
      expect(find.textContaining('Request reference:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [true, false]) {
    testWidgets('deletion form fits 320dp at 200% text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, RequestsFake(), dark: dark, scale: 2);
      await tester.scrollUntilVisible(
        find.text('Submit deletion request'),
        400,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'signed-out users can read privacy but cannot access protected deletion form',
    (tester) async {
      final container = await pumpGym(tester);
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go(AppRoutes.privacySupport);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacySupportPage), findsOneWidget);
      container.read(appRouterProvider).go(AppRoutes.accountDeletion);
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionPage), findsNothing);
      expect(find.text('Sign in to your account'), findsOneWidget);
    },
  );
  testWidgets('privacy remains public during a recoverable restoration error', (
    tester,
  ) async {
    final api = FakeAuthApi()
      ..refreshFailure = const AuthFailure(AuthFailureKind.network);
    final container = await pumpGym(
      tester,
      api: api,
      storage: FakeCredentialStorage()..value = syntheticCredential(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not restore your session'), findsOneWidget);
    container.read(appRouterProvider).go(AppRoutes.privacySupport);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacySupportPage), findsOneWidget);
  });
}
