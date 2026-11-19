import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/main.dart' as entrypoint;

import 'features/auth/auth_widget_harness.dart';

void main() {
  testWidgets('entrypoint starts the application without a backend', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    entrypoint.main();
    // Decorative autoplay intentionally never settles; advance startup explicitly.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup without credentials reaches login', (tester) async {
    await pumpGym(tester);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Restoring your session…'), findsNothing);
  });

  testWidgets('development home requires an authenticated session', (
    tester,
  ) async {
    final container = await pumpGym(tester);
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('You are signed in.'), findsNothing);
    expect(find.text('Sign in to your account'), findsOneWidget);
  });

  for (final scenario in [
    (environment: 'staging', release: false),
    (environment: 'production', release: false),
    (environment: 'production', release: true),
  ]) {
    testWidgets(
      'home protected for ${scenario.environment}, release=${scenario.release}',
      (tester) async {
        final container = await pumpGym(
          tester,
          config: AppConfig.fromValues(
            environmentName: scenario.environment,
            apiBaseUrl: scenario.release
                ? AppConfig.productionApiBaseUrl
                : 'https://api.example.invalid/api/v1/',
            isRelease: scenario.release,
          ),
        );
        await tester.pumpAndSettle();
        container.read(appRouterProvider).go(AppRoutes.home);
        await tester.pumpAndSettle();
        expect(find.text('You are signed in.'), findsNothing);
        expect(find.text('Sign in to your account'), findsOneWidget);
      },
    );
  }

  testWidgets('unknown route has a recoverable fallback', (tester) async {
    final container = await pumpGym(tester);
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/missing-page');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
    await tester.tap(find.text('Return to start'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
  });

  testWidgets('root route resolves according to session state', (tester) async {
    final container = await pumpGym(tester);
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/');
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
  });
}
