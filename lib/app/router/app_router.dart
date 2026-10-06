import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../shared/widgets/message_page.dart';
import '../navigation/foundation_screens.dart';
import 'app_routes.dart';

GoRouter createAppRouter(AppConfig config) {
  return GoRouter(
    initialLocation: AppRoutes.startup,
    redirect: (context, state) {
      if (state.uri.path == '/') return AppRoutes.startup;
      if (state.uri.path == AppRoutes.developmentHome &&
          !config.developmentHomeEnabled) {
        return AppRoutes.login;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        builder: (context, state) =>
            StartupScreen(showDevelopmentHome: config.developmentHomeEnabled),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPlaceholderScreen(),
      ),
      if (config.developmentHomeEnabled)
        GoRoute(
          path: AppRoutes.developmentHome,
          builder: (context, state) => const DevelopmentHomeScreen(),
        ),
    ],
    errorBuilder: (context, state) => MessagePage(
      title: 'Page not found',
      message: 'This page is unavailable. Return to the start to continue.',
      actions: [
        FilledButton(
          onPressed: () => context.go(AppRoutes.startup),
          child: const Text('Return to start'),
        ),
      ],
    ),
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(ref.watch(appConfigProvider));
  ref.onDispose(router.dispose);
  return router;
});
