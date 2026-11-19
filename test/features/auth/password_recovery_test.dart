import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/network/api_client.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/auth/data/password_recovery_repository.dart';
import 'package:gym_management_app/features/auth/presentation/password_recovery_page.dart';
import 'auth_fakes.dart';

class RecoveryFake implements PasswordRecoveryRepository {
  int requests = 0, completions = 0;
  Completer<void>? gate;
  PasswordRecoveryFailure? failure;
  @override
  Future<void> request(String email, CancelToken cancel) async {
    requests++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> complete(
    String token,
    String password,
    CancelToken cancel,
  ) async {
    completions++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  test(
    'public transport uses approved contract without stale credentials or redirects',
    () async {
      final client = createApiClient(
        AppConfig.fromValues(apiBaseUrl: 'https://api.example.test/api/v1/'),
      );
      addTearDown(() => client.close(force: true));
      client.options.headers.addAll({
        'Authorization': 'synthetic-stale',
        'Cookie': 'synthetic-cookie',
        'Origin': 'https://stale.test',
      });
      final repository = DioPasswordRecoveryRepository(client);
      for (final complete in [false, true]) {
        client.httpClientAdapter = CallbackAdapter((request) {
          expect(request.method, 'POST');
          expect(
            request.path,
            'auth/password-recovery/${complete ? 'complete' : 'request'}',
          );
          for (final key in ['Authorization', 'Cookie', 'Origin']) {
            expect(request.headers[key], isNull);
          }
          expect(request.followRedirects, false);
          expect(
            request.data,
            complete
                ? {
                    'token': 'A' * 43,
                    'newPassword': ' synthetic passphrase preserved ',
                  }
                : {'email': 'synthetic@example.test'},
          );
          return jsonResponse({
            'success': true,
            'data': {complete ? 'passwordChanged' : 'accepted': true},
          }, status: complete ? 200 : 202);
        });
        if (complete) {
          await repository.complete(
            ' ${'A' * 43} ',
            ' synthetic passphrase preserved ',
            CancelToken(),
          );
        } else {
          await repository.request(' synthetic@example.test ', CancelToken());
        }
      }
    },
  );
  for (final status in [200, 202]) {
    test(
      'never treats an unconfirmed response as successful ($status)',
      () async {
        final client = Dio(
          BaseOptions(baseUrl: 'https://api.example.test/api/v1/'),
        );
        addTearDown(() => client.close(force: true));
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': true,
            'data': {'accepted': false},
          }, status: status),
        );
        expect(
          DioPasswordRecoveryRepository(
            client,
          ).request('synthetic@example.test', CancelToken()),
          throwsA(isA<PasswordRecoveryFailure>()),
        );
      },
    );
  }
  for (final scenario in [
    (404, 'NOT_FOUND'),
    (503, 'PASSWORD_RECOVERY_UNAVAILABLE'),
    (401, 'INVALID_RECOVERY_CREDENTIAL'),
    (429, 'RATE_LIMITED'),
  ]) {
    test(
      'safe error mapping ${scenario.$2} hides raw server details',
      () async {
        final client = Dio(
          BaseOptions(baseUrl: 'https://api.example.test/api/v1/'),
        );
        addTearDown(() => client.close(force: true));
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({
            'success': false,
            'error': {
              'code': scenario.$2,
              'message': 'private SMTP password or code',
            },
          }, status: scenario.$1),
        );
        try {
          await DioPasswordRecoveryRepository(
            client,
          ).request('synthetic@example.test', CancelToken());
          fail('Expected a typed failure');
        } on PasswordRecoveryFailure catch (failure) {
          expect(failure.message, isNot(contains('private SMTP')));
        }
      },
    );
  }

  Future<void> mount(
    WidgetTester tester,
    RecoveryFake repository, {
    bool dark = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passwordRecoveryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const PasswordRecoveryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pump();
  }

  Future<void> input(WidgetTester tester, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  testWidgets(
    'generic acceptance is explicit about unverified delivery and existence',
    (tester) async {
      final fake = RecoveryFake();
      await mount(tester, fake);
      await input(tester, 'recoveryEmail', 'synthetic@example.test');
      await tapText(tester, 'Request code');
      await tester.pumpAndSettle();
      expect(fake.requests, 1);
      expect(find.textContaining('does not confirm delivery'), findsOneWidget);
    },
  );
  testWidgets('busy state prevents duplicate dispatch and back dismissal', (
    tester,
  ) async {
    final fake = RecoveryFake()..gate = Completer<void>();
    await mount(tester, fake);
    await input(tester, 'recoveryEmail', 'synthetic@example.test');
    await tapText(tester, 'Request code');
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, false);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Back to login',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Request code'));
    expect(fake.requests, 1);
    fake.gate!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets(
    'confirmation and strong password are required, then success clears sensitive fields',
    (tester) async {
      final fake = RecoveryFake();
      await mount(tester, fake);
      await input(tester, 'recoveryToken', 'B' * 43);
      final password = syntheticCredential();
      await input(tester, 'recoveryPassword', password);
      await input(tester, 'recoveryConfirmation', 'different');
      await tapText(tester, 'Change password');
      expect(fake.completions, 0);
      expect(find.text('Passwords must match.'), findsOneWidget);
      await input(tester, 'recoveryConfirmation', password);
      await tapText(tester, 'Change password');
      await tester.pumpAndSettle();
      expect(fake.completions, 1);
      expect(find.text('Password changed'), findsOneWidget);
      expect(find.byKey(const ValueKey('recoveryToken')), findsNothing);
    },
  );
  testWidgets('delivery errors never show a false success message', (
    tester,
  ) async {
    final fake = RecoveryFake()
      ..failure = const PasswordRecoveryFailure(
        'Recovery email delivery is unavailable.',
      );
    await mount(tester, fake);
    await input(tester, 'recoveryEmail', 'synthetic@example.test');
    await tapText(tester, 'Request code');
    await tester.pumpAndSettle();
    expect(find.textContaining('Request accepted.'), findsNothing);
    expect(
      find.text('Recovery email delivery is unavailable.'),
      findsOneWidget,
    );
  });
  for (final dark in [false, true]) {
    testWidgets(
      'narrow layout and large text remain readable (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, RecoveryFake(), dark: dark, textScale: 2);
        await tester.scrollUntilVisible(
          find.text('Change password'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
