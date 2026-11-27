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
import '../../../app/theme/design_tokens.dart';
import '../../../shared/contact/member_contact.dart';
import '../../../shared/widgets/round_action.dart';
import '../../members/presentation/member_list_widgets.dart';
import '../../personal_training/pt.dart';
import '../models/trainer_models.dart';

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
          else if (trainer != null) ...[
            // Who, at a glance.
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(
                    trainer.firstName.characters.first.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          trainer.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Trainer code: ${trainer.trainerCode}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          StatusPill(
                            label:
                                '${trainer.status.name[0].toUpperCase()}${trainer.status.name.substring(1)}',
                            tone: trainer.status == TrainerStatus.active
                                ? AppTone.positive
                                : AppTone.neutral,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            RoundActionRow(
              actions: [
                RoundAction(
                  icon: Icons.call_outlined,
                  label: 'Call',
                  onTap: () => callMember(context, trainer.phone),
                ),
                RoundAction(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  onTap: () => whatsappMember(
                    context,
                    trainer.phone,
                    'Hi ${trainer.firstName},',
                  ),
                ),
                RoundAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit trainer',
                  onTap: () => context.push(trainerPath(scope, edit: true)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _TrainerWorkLine(gymId: scope.gymId, trainerId: trainer.id),
            ProfileSection(
              title: 'Details',
              children: [
                IconLabel(trainer.phone, icon: Icons.phone_outlined),
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
                    trainer.address!.display,
                    icon: Icons.location_on_outlined,
                  ),
                IconLabel(
                  (trainer.specializations ?? []).isEmpty
                      ? 'No specializations provided.'
                      : trainer.specializations!.join(', '),
                  icon: Icons.fitness_center_outlined,
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
              ],
            ),
          ],
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

/// What this trainer is doing now, in one line: their active PT clients.
class _TrainerWorkLine extends ConsumerWidget {
  const _TrainerWorkLine({required this.gymId, required this.trainerId});
  final String gymId, trainerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final packages = ref.watch(
      ptPackagesProvider((memberId: null, trainerId: trainerId, status: null)),
    );
    final text = switch (packages) {
      AsyncData(:final value?) => () {
        final active = value.where((pkg) => pkg.status == PtStatus.active);
        if (active.isEmpty) return 'No active PT clients';
        final left = active.fold<int>(0, (sum, pkg) => sum + pkg.sessionsLeft);
        return '${active.length} active PT ${active.length == 1 ? 'client' : 'clients'} · $left sessions left';
      }(),
      AsyncError() => 'PT clients could not be loaded',
      _ => 'Loading PT clients…',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.sports_gymnastics_outlined, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
