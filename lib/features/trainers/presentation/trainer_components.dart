import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../data/trainer_failure.dart';
import '../providers/trainer_providers.dart';

String trainerPath(TrainerScope scope, {bool edit = false}) =>
    '${AppRoutes.trainers}/${scope.trainerId}${edit ? '/edit' : ''}?gymId=${Uri.encodeQueryComponent(scope.gymId)}';

class TrainerError extends StatelessWidget {
  const TrainerError({super.key, required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            error is TrainerFailure
                ? (error as TrainerFailure).message
                : 'Trainer information could not be loaded. Please try again.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class TrainerContextChanged extends StatelessWidget {
  const TrainerContextChanged({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The gym context changed. Return to Trainers to continue.',
          ),
          TextButton(
            onPressed: () => context.go(AppRoutes.trainers),
            child: const Text('Return to Trainers'),
          ),
        ],
      ),
    ),
  );
}
