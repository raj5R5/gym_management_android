import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_failure.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/auth/providers/session_controller.dart';
import '../../shared/widgets/message_page.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      title: loggingOut ? 'Signing out…' : 'Welcome, ${name ?? ''}',
      message: loggingOut
          ? 'Ending your session securely.'
          : 'You are signed in.',
      actions: [
        FilledButton(
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
