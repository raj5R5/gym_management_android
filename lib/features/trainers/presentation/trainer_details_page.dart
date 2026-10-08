import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/trainer_failure.dart';
import '../providers/trainer_providers.dart';
import 'trainer_components.dart';

class TrainerDetailsPage extends ConsumerWidget {
  const TrainerDetailsPage({
    super.key,
    required this.trainerId,
    required this.gymId,
  });
  final String trainerId;
  final String? gymId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != gymId) return const TrainerContextChanged();
    final scope = scopeFor(gym, trainerId);
    final state = ref.watch(trainerDetailProvider(scope));
    final trainer = state.asData?.value;
    Future<void> refresh() async {
      ref.invalidate(trainerDetailProvider(scope));
      try {
        await ref.read(trainerDetailProvider(scope).future);
      } on TrainerFailure {
        /* AsyncValue renders the safe error. */
      }
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to Trainers',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.trainers);
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Trainer details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (state.hasError)
            TrainerError(error: state.error, retry: refresh)
          else if (trainer != null)
            ProfileSection(
              title: trainer.name,
              children: [
                Text('Trainer code: ${trainer.trainerCode}'),
                Text('Phone: ${trainer.phone}'),
                Text('Status: ${trainer.status.name}'),
                Text(
                  trainer.branchId == null
                      ? 'No branch assigned'
                      : 'Branch ID: ${trainer.branchId}',
                ),
                if (trainer.dateOfBirth != null)
                  Text('Date of birth: ${trainer.dateOfBirth}'),
                if (trainer.gender != null)
                  Text('Gender: ${trainer.gender!.replaceAll('_', ' ')}'),
                if (trainer.address != null)
                  Text('Address: ${trainer.address!.display}'),
                const SizedBox(height: 12),
                Text(
                  'Specializations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  (trainer.specializations ?? []).isEmpty
                      ? 'No specializations provided.'
                      : trainer.specializations!.join(', '),
                ),
                if (trainer.createdAt != null)
                  Text(
                    'Created: ${trainer.createdAt!.toUtc().toIso8601String()} (UTC)',
                  ),
                if (trainer.updatedAt != null)
                  Text(
                    'Updated: ${trainer.updatedAt!.toUtc().toIso8601String()} (UTC)',
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(trainerPath(scope, edit: true)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit trainer'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
