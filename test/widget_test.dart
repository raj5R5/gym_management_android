import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/main.dart' as entrypoint;

Future<ProviderContainer> pumpFoundation(
  WidgetTester tester,
  AppConfig config,
) async {
  final container = ProviderContainer(
    overrides: [appConfigProvider.overrideWithValue(config)],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const GymApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('entrypoint starts the application without a backend', (
    tester,
  ) async {
    entrypoint.main();
    await tester.pumpAndSettle();
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.text('Welcome to Gym Management'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup navigates to login and back', (tester) async {
    await pumpFoundation(tester, AppConfig.fromValues());
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in coming soon'), findsOneWidget);
    await tester.tap(find.text('Return to start'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Gym Management'), findsOneWidget);
  });

  testWidgets('development preview is reachable and can return', (
    tester,
  ) async {
    await pumpFoundation(tester, AppConfig.fromValues());
    await tester.tap(find.text('Open development preview'));
    await tester.pumpAndSettle();
    expect(find.text('Development preview'), findsOneWidget);
    await tester.tap(find.text('Return to start'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Gym Management'), findsOneWidget);
  });

  for (final scenario in [
    (environment: 'staging', release: false),
    (environment: 'production', release: false),
    (environment: 'development', release: true),
  ]) {
    testWidgets(
      'preview blocked for ${scenario.environment}, release=${scenario.release}',
      (tester) async {
        final container = await pumpFoundation(
          tester,
          AppConfig.fromValues(
            environmentName: scenario.environment,
            apiBaseUrl: 'https://api.example.test/v1',
            isRelease: scenario.release,
          ),
        );
        expect(find.text('Open development preview'), findsNothing);
        container.read(appRouterProvider).go(AppRoutes.developmentHome);
        await tester.pumpAndSettle();
        expect(find.text('Development preview'), findsNothing);
        expect(find.text('Sign-in coming soon'), findsOneWidget);
      },
    );
  }

  testWidgets('unknown route has a recoverable fallback', (tester) async {
    final container = await pumpFoundation(tester, AppConfig.fromValues());
    container.read(appRouterProvider).go('/missing-page');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
    await tester.tap(find.text('Return to start'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Gym Management'), findsOneWidget);
  });

  testWidgets('root route resolves to startup', (tester) async {
    final container = await pumpFoundation(tester, AppConfig.fromValues());
    container.read(appRouterProvider).go('/');
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Gym Management'), findsOneWidget);
  });
}
