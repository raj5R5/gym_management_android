import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_dashboard/presentation/dashboard_page.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/providers/session_controller.dart';
import '../../shared/widgets/message_page.dart';
import '../navigation/admin_shell.dart';
import '../navigation/foundation_screens.dart';
import 'app_routes.dart';

GoRouter createAppRouter({
  required SessionState Function() session,
  required Listenable refreshListenable,
}) {
  return GoRouter(
    initialLocation: AppRoutes.startup,
    refreshListenable: refreshListenable,
    redirect: (context, route) {
      final current = session();
      final path = route.uri.path;
      String? target;
      final isAdmin =
          current is SessionAuthenticated &&
          current.identity.user.status == AccountStatus.active &&
          current.identity.gymAccess.any(
            (grant) =>
                grant.role == AuthRole.admin &&
                grant.status == AccountStatus.active,
          );
      final adminPath = path.startsWith('${AppRoutes.home}/');
      if (current is SessionInitial ||
          current is SessionLoading &&
              (current.operation == SessionOperation.restoring ||
                  current.operation == SessionOperation.refreshing)) {
        target = AppRoutes.startup;
      } else if (current is SessionLoading &&
          current.operation == SessionOperation.loggingOut) {
        target = AppRoutes.home;
      } else if (current is SessionAuthenticated) {
        if (path == '/' ||
            path == AppRoutes.startup ||
            path == AppRoutes.login ||
            (path == AppRoutes.home && isAdmin)) {
          target = isAdmin ? AppRoutes.dashboard : AppRoutes.home;
        }
        if (adminPath && !isAdmin) target = AppRoutes.home;
      } else {
        if (path == '/' ||
            path == AppRoutes.startup ||
            path == AppRoutes.home ||
            adminPath) {
          target = AppRoutes.login;
        }
      }
      return target == path ? null : target;
    },
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        builder: (_, _) => const StartupScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const AuthenticatedHomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, _) => const DashboardPage(),
          ),
          GoRoute(
            path: AppRoutes.members,
            builder: (_, _) => const AdminComingSoonPage(title: 'Members'),
          ),
          GoRoute(
            path: AppRoutes.trainers,
            builder: (_, _) => const AdminComingSoonPage(title: 'Trainers'),
          ),
          GoRoute(
            path: AppRoutes.more,
            builder: (_, _) => const AuthenticatedHomeScreen(embedded: true),
          ),
        ],
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
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, _) => refresh.value++);
  final router = createAppRouter(
    session: () => ref.read(sessionControllerProvider),
    refreshListenable: refresh,
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
