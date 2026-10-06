import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/message_page.dart';
import '../router/app_routes.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, required this.showDevelopmentHome});

  final bool showDevelopmentHome;

  @override
  Widget build(BuildContext context) {
    return MessagePage(
      title: 'Welcome to Gym Management',
      message:
          'Manage your gym in one place. More functionality is coming soon.',
      actions: [
        FilledButton(
          onPressed: () => context.go(AppRoutes.login),
          child: const Text('Continue'),
        ),
        if (showDevelopmentHome)
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.developmentHome),
            child: const Text('Open development preview'),
          ),
      ],
    );
  }
}

class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MessagePage(
      title: 'Sign-in coming soon',
      message: 'Sign-in is not available yet.',
      actions: [
        TextButton(
          onPressed: () => context.go(AppRoutes.startup),
          child: const Text('Return to start'),
        ),
      ],
    );
  }
}

/// Temporary navigation target; it does not establish an authenticated user.
class DevelopmentHomeScreen extends StatelessWidget {
  const DevelopmentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MessagePage(
      title: 'Development preview',
      message:
          'This temporary home is for development only. '
          'No user is signed in and no gym data is loaded.',
      actions: [
        TextButton(
          onPressed: () => context.go(AppRoutes.startup),
          child: const Text('Return to start'),
        ),
      ],
    );
  }
}
