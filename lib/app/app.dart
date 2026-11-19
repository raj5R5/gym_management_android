import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_failure.dart';
import '../features/auth/models/session_state.dart';
import '../features/auth/providers/session_controller.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../shared/widgets/titanium_surface.dart';
import '../shared/widgets/ambient_motion.dart';

class GymApp extends ConsumerStatefulWidget {
  const GymApp({super.key, this.animateDecorations = true});
  final bool animateDecorations;

  @override
  ConsumerState<GymApp> createState() => _GymAppState();
}

class _GymAppState extends ConsumerState<GymApp> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(sessionControllerProvider, (_, session) {
      if (session is SessionInitial) _restoreSession();
    }, fireImmediately: true);
  }

  Future<void> _restoreSession() async {
    // Defer mutations until the initial widget/provider build has completed.
    await Future<void>.value();
    if (!mounted || ref.read(sessionControllerProvider) is! SessionInitial) {
      return;
    }
    try {
      await ref.read(sessionControllerProvider.notifier).restoreSession();
    } on AuthFailure {
      // Recovery publishes SessionError, preserving credentials when retryable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MuscleDesk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => AmbientMotionSettings(
        enabled: widget.animateDecorations,
        child: TitaniumCanvas(child: child ?? const SizedBox.shrink()),
      ),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
