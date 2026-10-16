import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin_dashboard/providers/dashboard_providers.dart';
import '../router/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_failure.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/providers/session_controller.dart';
import '../../shared/widgets/message_page.dart';
import '../../shared/widgets/brand_mark.dart';
import '../../shared/widgets/profile_section.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(),
            SizedBox(height: 32),
            CircularProgressIndicator(semanticsLabel: 'Restoring session'),
            SizedBox(height: 24),
            Text('Gym Management'),
            SizedBox(height: 8),
            Text('Restoring your session…'),
          ],
        ),
      ),
    ),
  );
}

/// Authenticated navigation placeholder. No gym features or extra API calls.
class AuthenticatedHomeScreen extends ConsumerWidget {
  const AuthenticatedHomeScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final loggingOut =
        session is SessionLoading &&
        session.operation == SessionOperation.loggingOut;
    if (session is! SessionAuthenticated && !loggingOut) {
      return const SizedBox.shrink();
    }
    final user = session is SessionAuthenticated ? session.identity.user : null;
    final displayName = user?.displayName?.trim();
    final name = displayName != null && displayName.isNotEmpty
        ? displayName
        : user?.email;
    return MessagePage(
      embedded: embedded,
      alignment: embedded ? Alignment.topCenter : Alignment.center,
      title: loggingOut
          ? 'Signing out…'
          : embedded
          ? 'Your workspace'
          : 'Welcome, ${name ?? ''}',
      message: loggingOut
          ? 'Ending your session securely.'
          : embedded
          ? 'Account and gym management.'
          : 'You are signed in.',
      actions: [
        if (!loggingOut && user != null)
          ProfileSection(
            title: 'Your account',
            icon: Icons.person_outline,
            children: [
              Text(user.email, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              const Text('Manage your gym from one workspace.'),
            ],
          ),
        if (embedded && ref.watch(adminGymProvider) != null)
          OutlinedButton(
            onPressed: loggingOut ? null : () => context.push(AppRoutes.plans),
            child: const Text('Membership Plans'),
          ),
        FilledButton(
          style: AppButtonStyles.warning(context),
          onPressed: user == null || loggingOut
              ? null
              : () async {
                  try {
                    await ref.read(sessionControllerProvider.notifier).logout();
                  } on AuthFailure {
                    // Cleanup failures are published as safe errors on the login page.
                  }
                },
          child: loggingOut
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface,
                        semanticsLabel: 'Logging out',
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Logging out…'),
                  ],
                )
              : const Text('Logout'),
        ),
      ],
    );
  }
}
