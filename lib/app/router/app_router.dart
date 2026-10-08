import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_dashboard/presentation/dashboard_page.dart';
import '../../features/members/presentation/members_page.dart';
import '../../features/members/presentation/member_details_page.dart';
import '../../features/members/presentation/member_form_page.dart';
import '../../features/memberships/presentation/membership_page.dart';
import '../../features/memberships/presentation/purchase_page.dart';
import '../../features/memberships/presentation/plans_page.dart';
import '../../features/memberships/presentation/membership_detail_page.dart';
import '../../features/trainers/presentation/trainers_page.dart';
import '../../features/trainers/presentation/trainer_details_page.dart';
import '../../features/trainers/presentation/trainer_form_page.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/providers/session_controller.dart';
import '../../shared/widgets/message_page.dart';
import '../navigation/admin_shell.dart';
import '../navigation/foundation_screens.dart';
import 'app_routes.dart';
import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/attendance/presentation/check_in_page.dart';

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
      final profileRoute =
          path == AppRoutes.attendance ||
          path.startsWith('${AppRoutes.attendance}/') ||
          path == AppRoutes.plans ||
          path.startsWith('${AppRoutes.plans}/') ||
          path == AppRoutes.members ||
          path.startsWith('${AppRoutes.members}/') ||
          path == AppRoutes.trainers ||
          path.startsWith('${AppRoutes.trainers}/');
      if (current is SessionInitial ||
          current is SessionLoading &&
              current.operation == SessionOperation.restoring) {
        target = AppRoutes.startup;
      } else if (current is SessionLoading &&
          current.operation == SessionOperation.refreshing) {
        // Retain profile forms/read scopes during interceptor recovery. AdminShell
        // hides the protected subtree and shows startup until recovery finishes.
        target = profileRoute ? null : AppRoutes.startup;
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
            builder: (_, _) => const MembersPageView(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) =>
                    MemberFormPage(gymId: state.uri.queryParameters['gymId']),
              ),
              GoRoute(
                path: ':memberId',
                builder: (_, state) => MemberDetailsPage(
                  memberId: state.pathParameters['memberId']!,
                  gymId: state.uri.queryParameters['gymId'],
                ),
                routes: [
                  GoRoute(
                    path: 'membership',
                    builder: (_, state) => MembershipPage(
                      memberId: state.pathParameters['memberId']!,
                      gymId: state.uri.queryParameters['gymId'],
                    ),
                    routes: [
                      GoRoute(
                        path: 'purchase',
                        builder: (_, state) => PurchasePage(
                          memberId: state.pathParameters['memberId']!,
                          gymId: state.uri.queryParameters['gymId'],
                        ),
                      ),
                      GoRoute(
                        path: ':subscriptionId',
                        builder: (_, state) => MembershipDetailPage(
                          memberId: state.pathParameters['memberId']!,
                          subscriptionId:
                              state.pathParameters['subscriptionId']!,
                          gymId: state.uri.queryParameters['gymId'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => MemberFormPage(
                      memberId: state.pathParameters['memberId']!,
                      gymId: state.uri.queryParameters['gymId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.trainers,
            builder: (_, _) => const TrainersPageView(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) =>
                    TrainerFormPage(gymId: state.uri.queryParameters['gymId']),
              ),
              GoRoute(
                path: ':trainerId',
                builder: (_, state) => TrainerDetailsPage(
                  trainerId: state.pathParameters['trainerId']!,
                  gymId: state.uri.queryParameters['gymId'],
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => TrainerFormPage(
                      trainerId: state.pathParameters['trainerId']!,
                      gymId: state.uri.queryParameters['gymId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.plans,
            builder: (_, _) => const PlansPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) =>
                    PlanFormPage(gymId: state.uri.queryParameters['gymId']),
              ),
              GoRoute(
                path: ':planId',
                builder: (_, state) => PlanFormPage(
                  gymId: state.uri.queryParameters['gymId'],
                  planId: state.pathParameters['planId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.attendance,
            builder: (_, _) => const AttendancePageView(),
            routes: [
              GoRoute(
                path: 'check-in',
                builder: (_, state) => CheckInPage(
                  gymId: state.uri.queryParameters['gymId'],
                  selectOnly: state.uri.queryParameters['mode'] == 'filter',
                ),
              ),
            ],
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
