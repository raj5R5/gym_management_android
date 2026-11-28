import 'package:flutter/material.dart';
import '../../features/branches/branches_page.dart';
import '../../features/leads/lead_detail_page.dart';
import '../../features/leads/leads_page.dart';
import '../../features/leads/leads.dart';
import '../../features/expenses/expenses_page.dart';
import '../../features/member_app/activation_page.dart';
import '../../features/member_app/payment_claims.dart';
import '../../features/reports/reports.dart';
import '../../features/reports/reports_page.dart';
import '../../features/personal_training/pt_pages.dart';
import '../../features/personal_training/trainer_home_page.dart';
import '../../features/visits/today_visits_page.dart';
import '../../features/visits/qr_scan_page.dart';
import '../../features/visits/check_in_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/gym_settings/gym_settings_page.dart';

import '../../features/admin_dashboard/presentation/dashboard_page.dart';
import '../../features/members/presentation/members_page.dart';
import '../../features/members/presentation/member_details_page.dart';
import '../../features/members/presentation/member_form_page.dart';
import '../../features/members/presentation/member_onboarding_page.dart';
import '../../features/memberships/presentation/membership_page.dart';
import '../../features/memberships/presentation/purchase_page.dart';
import '../../features/memberships/presentation/plans_page.dart';
import '../../features/memberships/presentation/membership_detail_page.dart';
import '../../features/memberships/presentation/revenue_details_page.dart';
import '../../features/memberships/presentation/outstanding_dues_page.dart';
import '../../features/trainers/presentation/trainers_page.dart';
import '../../features/trainers/presentation/trainer_details_page.dart';
import '../../features/trainers/presentation/trainer_form_page.dart';
import '../../features/owner_profile/owner_profile_page.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/phone_sign_in_page.dart';
import '../../features/gym_join/join_requests_page.dart';
import '../../features/auth/presentation/owner_signup_page.dart';
import '../../features/auth/presentation/password_recovery_page.dart';
import '../../features/account_privacy/privacy_support_page.dart';
import '../../features/account_privacy/account_deletion_page.dart';
import '../../features/auth/models/owner_registration.dart';
import '../../features/auth/providers/session_controller.dart';
import '../../shared/widgets/message_page.dart';
import '../navigation/admin_shell.dart';
import '../navigation/form_navigation_guard.dart';
import '../navigation/foundation_screens.dart';
import 'app_routes.dart';
import '../../features/members/import/member_import_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/account_security/account_security_page.dart';

/// Where [path] should go for [current]; null keeps it. Pure, for testing.
String? appRedirect(SessionState current, String path) {
  // Public policy/help must remain reachable even during restoration errors.
  if (path == AppRoutes.privacySupport) return null;
  if (path == AppRoutes.passwordRecovery) return null;
  if (path == AppRoutes.activate) return null;
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
  // Any shell page survives access-token recovery: AdminShell keeps it
  // offstage behind the startup screen until the session is back.
  final profileRoute =
      path == AppRoutes.accountDeletion ||
      path.startsWith('${AppRoutes.home}/');
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
  } else if (current is SessionError && current.canRetryRestoration) {
    // Keep a recoverable startup failure separate from an invalid session.
    // Signing in remains an explicit alternative to retrying restoration.
    target = path == AppRoutes.login || path == AppRoutes.welcome
        ? null
        : AppRoutes.startup;
  } else if (current is SessionAuthenticated) {
    if (path == '/' ||
        path == AppRoutes.startup ||
        path == AppRoutes.login ||
        path == AppRoutes.welcome ||
        path == AppRoutes.signup ||
        (path == AppRoutes.home && isAdmin)) {
      target = isAdmin ? AppRoutes.dashboard : AppRoutes.home;
    }
    if (adminPath && !isAdmin) target = AppRoutes.home;
  } else {
    if (path == '/' ||
        path == AppRoutes.startup ||
        path == AppRoutes.home ||
        path == AppRoutes.accountDeletion ||
        adminPath) {
      target = AppRoutes.welcome;
    }
  }
  return target == path ? null : target;
}

GoRouter createAppRouter({
  required SessionState Function() session,
  required Listenable refreshListenable,
}) {
  Future<bool> protectForm(BuildContext context, GoRouterState state) async {
    // Session redirects remain authoritative; draft dialogs cannot retain a
    // protected route after authentication is lost.
    if (session() is! SessionAuthenticated) return true;
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(formNavigationGuardProvider).allowExit(path: state.uri.path);
  }

  return GoRouter(
    initialLocation: AppRoutes.startup,
    refreshListenable: refreshListenable,
    redirect: (context, route) => appRedirect(session(), route.uri.path),
    routes: [
      GoRoute(
        path: AppRoutes.passwordRecovery,
        builder: (_, _) => const PasswordRecoveryPage(),
      ),
      GoRoute(
        path: AppRoutes.activate,
        builder: (_, _) => const ActivationPage(),
      ),
      GoRoute(
        path: AppRoutes.privacySupport,
        builder: (_, _) => const PrivacySupportPage(),
      ),
      GoRoute(
        path: AppRoutes.accountDeletion,
        builder: (_, _) => const AccountDeletionPage(),
      ),
      GoRoute(
        path: AppRoutes.startup,
        builder: (_, _) => const StartupScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const PhoneSignInPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, state) => LoginPage(
          registrationSucceeded: state.extra is OwnerRegistrationSuccess,
        ),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, _) => const OwnerSignupPage(),
      ),
      GoRoute(path: AppRoutes.home, builder: (_, _) => const RoleHome()),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, _) => const DashboardPage(),
            routes: [
              GoRoute(
                path: 'revenue',
                builder: (_, state) => RevenueDetailsPage(
                  gymId: state.uri.queryParameters['gymId'],
                  from: state.uri.queryParameters['from'],
                  to: state.uri.queryParameters['to'],
                ),
              ),
              GoRoute(
                path: 'dues',
                builder: (_, state) => OutstandingDuesPage(
                  gymId: state.uri.queryParameters['gymId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.members,
            builder: (_, _) => const MembersPageView(),
            routes: [
              GoRoute(
                path: 'new',
                onExit: protectForm,
                builder: (_, state) => MemberOnboardingPage(
                  gymId: state.uri.queryParameters['gymId'],
                  existing: state.uri.queryParameters['existing'] == '1',
                  // Converting an enquiry passes its name and phone in memory,
                  // never in the URL.
                  prefill: state.extra is LeadPrefill
                      ? state.extra! as LeadPrefill
                      : null,
                ),
              ),
              GoRoute(
                path: 'import',
                builder: (_, _) => const MemberImportPage(),
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
                    onExit: protectForm,
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
            builder: (_, state) => PlansPage(
              initialActiveOnly:
                  state.uri.queryParameters['status'] == 'active',
            ),
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
            path: AppRoutes.branches,
            builder: (_, _) => const BranchesPage(),
          ),
          GoRoute(
            path: AppRoutes.leads,
            builder: (_, _) => const LeadsPage(),
            routes: [
              GoRoute(
                path: ':leadId',
                builder: (_, state) =>
                    LeadDetailPage(leadId: state.pathParameters['leadId']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.notifications,
            builder: (_, _) => const NotificationsPage(),
          ),
          GoRoute(
            path: AppRoutes.reports,
            builder: (_, _) => const ReportsPage(),
            routes: [
              GoRoute(
                path: ':kind',
                builder: (_, state) {
                  final kind = ReportKind.parse(state.pathParameters['kind']!);
                  return kind == null
                      ? const ReportsPage()
                      : ReportPage(kind: kind);
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.paymentClaims,
            builder: (_, _) => const PaymentClaimsPage(),
          ),
          GoRoute(
            path: AppRoutes.pt,
            builder: (_, _) => const PtPage(),
            routes: [
              GoRoute(
                path: ':packageId',
                builder: (_, state) => PtPackageDetailPage(
                  packageId: state.pathParameters['packageId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.expenses,
            builder: (_, _) => const ExpensesPage(),
          ),
          GoRoute(
            path: AppRoutes.checkIn,
            builder: (_, _) => const CheckInPage(),
            routes: [
              GoRoute(path: 'scan', builder: (_, _) => const QrScanPage()),
              GoRoute(
                path: 'today',
                builder: (_, _) => const TodayVisitsPage(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.more,
            builder: (_, _) => const AuthenticatedHomeScreen(embedded: true),
            routes: [
              GoRoute(
                path: 'profile',
                builder: (_, _) => const OwnerProfilePage(),
                onExit: protectForm,
              ),
              GoRoute(
                path: 'settings',
                builder: (_, _) => const GymSettingsPage(),
              ),
              GoRoute(
                path: 'security',
                builder: (_, _) => const AccountSecurityPage(),
              ),
              GoRoute(
                path: 'join-requests',
                builder: (_, _) => const JoinRequestsPage(),
              ),
            ],
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
