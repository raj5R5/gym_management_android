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
import '../../shared/widgets/page_section.dart';
import '../../shared/widgets/profile_section.dart';
import '../../features/owner_profile/owner_profile_widgets.dart';
import '../../features/account_privacy/privacy_support_page.dart';

class StartupScreen extends ConsumerWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session is SessionError && session.canRetryRestoration) {
      return MessagePage(
        title: 'Could not restore your session',
        message:
            '${session.failure.message} Your saved sign-in has been kept. '
            'Retry when the connection or secure storage is available.',
        actions: [
          FilledButton(
            onPressed: () async {
              try {
                await ref
                    .read(sessionControllerProvider.notifier)
                    .restoreSession();
              } on AuthFailure {
                // The repository publishes the next safe recovery state.
              }
            },
            child: const Text('Retry session restoration'),
          ),
          TextButton(
            onPressed: () => context.go(AppRoutes.login),
            child: const Text('Sign in instead'),
          ),
        ],
      );
    }
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 52, child: BrandMark()),
              SizedBox(height: 32),
              CircularProgressIndicator(semanticsLabel: 'Restoring session'),
              SizedBox(height: 24),
              Text('MuscleDesk'),
              SizedBox(height: 8),
              Text('Restoring your session…'),
            ],
          ),
        ),
      ),
    );
  }
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
    if (embedded && !loggingOut && ref.watch(adminGymProvider) != null) {
      return _OwnerAccountPage(signedIn: user != null);
    }
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
        if (!loggingOut && embedded && ref.watch(adminGymProvider) != null)
          const OwnerAccountSection(),
        if (!loggingOut && user != null && !embedded)
          ProfileSection(
            title: 'Your account',
            icon: Icons.person_outline,
            children: [
              Text(user.email, style: Theme.of(context).textTheme.bodyLarge),
              if (ref.watch(adminGymProvider) != null) ...[
                const SizedBox(height: 8),
                const Text('Manage your gym from one workspace.'),
              ],
            ],
          ),
        if (embedded && ref.watch(adminGymProvider) != null)
          OutlinedButton.icon(
            onPressed: loggingOut
                ? null
                : () => context.push(AppRoutes.gymSettings),
            icon: const Icon(Icons.tune_outlined),
            label: const Text('Gym settings'),
          ),
        if (embedded && ref.watch(adminGymProvider) != null)
          OutlinedButton.icon(
            onPressed: loggingOut ? null : () => context.push(AppRoutes.plans),
            icon: const Icon(Icons.card_membership_outlined),
            label: const Text('Membership Plans'),
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
        if (!loggingOut) const PrivacySupportLink(),
        if (!loggingOut && user != null)
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.accountDeletion),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Request account deletion'),
          ),
      ],
    );
  }
}

/// The owner's account page: who is signed in, then the settings rows, with
/// signing out last and set apart.
class _OwnerAccountPage extends ConsumerWidget {
  const _OwnerAccountPage({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget row(IconData icon, String label, String route) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
    // A short page: build it whole so every action is always reachable.
    // Its own Material keeps the rows' ink inside this route.
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OwnerAccountSection(),
            ProfileSection(
              title: 'Gym',
              children: [
                SeparatedRows(
                  indent: 40,
                  children: [
                    row(
                      Icons.tune_outlined,
                      'Gym settings',
                      AppRoutes.gymSettings,
                    ),
                    row(
                      Icons.card_membership_outlined,
                      'Membership Plans',
                      AppRoutes.plans,
                    ),
                  ],
                ),
              ],
            ),
            ProfileSection(
              title: 'Account',
              children: [
                SeparatedRows(
                  indent: 40,
                  children: [
                    row(
                      Icons.policy_outlined,
                      'Privacy & support',
                      AppRoutes.privacySupport,
                    ),
                    if (signedIn)
                      row(
                        Icons.person_remove_outlined,
                        'Request account deletion',
                        AppRoutes.accountDeletion,
                      ),
                  ],
                ),
              ],
            ),
            FilledButton(
              style: AppButtonStyles.warning(context),
              onPressed: !signedIn
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(sessionControllerProvider.notifier)
                            .logout();
                      } on AuthFailure {
                        // Cleanup failures are published as safe errors on the login page.
                      }
                    },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
