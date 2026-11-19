import '../../../shared/formatting/payment_date.dart';
import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import 'trainer_app_access.dart';
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
              icon: Icons.fitness_center_outlined,
              children: [
                IconLabel(
                  'Trainer code: ${trainer.trainerCode}',
                  icon: Icons.badge_outlined,
                ),
                IconLabel(
                  'Phone: ${trainer.phone}',
                  icon: Icons.phone_outlined,
                ),
                IconLabel(
                  'Status: ${trainer.status.name}',
                  icon: Icons.verified_user_outlined,
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push(trainerPath(scope, edit: true)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit trainer'),
                ),
                const SizedBox(height: 12),
                if (trainer.dateOfBirth != null)
                  IconLabel(
                    'Date of birth: ${MaterialLocalizations.of(context).formatShortDate(trainer.dateOfBirth!.value)}',
                    icon: Icons.cake_outlined,
                  ),
                if (trainer.gender != null)
                  IconLabel(
                    'Gender: ${trainer.gender!.replaceAll('_', ' ')}',
                    icon: Icons.person_outline,
                  ),
                if (trainer.address != null)
                  IconLabel(
                    'Address: ${trainer.address!.display}',
                    icon: Icons.location_on_outlined,
                  ),
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
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline, size: 20),
                  title: const Text('Record details'),
                  children: [
                    if (trainer.createdAt != null)
                      IconLabel(
                        'Created: ${formatPaymentDateTime(MaterialLocalizations.of(context), trainer.createdAt!, timezone: 'UTC')}',
                        icon: Icons.event_available_outlined,
                      ),
                    if (trainer.updatedAt != null)
                      IconLabel(
                        'Updated: ${formatPaymentDateTime(MaterialLocalizations.of(context), trainer.updatedAt!, timezone: 'UTC')}',
                        icon: Icons.update,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          if (trainer != null && !state.isLoading && !state.hasError) ...[
            const SizedBox(height: 12),
            TrainerAppAccessCard(
              gymId: scope.gymId,
              trainer: trainer,
              onGranted: refresh,
            ),
          ],
        ],
      ),
    );
  }
}
