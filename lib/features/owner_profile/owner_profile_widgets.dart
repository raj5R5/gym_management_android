import '../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/profile_section.dart';
import '../../shared/widgets/soft_panel.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/session_controller.dart';
import 'owner_profile.dart';
import 'owner_signup_photo.dart';

class OwnerPhoto extends ConsumerWidget {
  const OwnerPhoto({
    super.key,
    this.profile,
    required this.name,
    this.size = 64,
  });
  final OwnerProfile? profile;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = profile == null ? null : ownerPhotoImage(ref, profile!);
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : '${parts.first.characters.first}${parts.length > 1 ? parts.last.characters.first : ''}'
              .toUpperCase();
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: 'Profile photo for $name',
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: image?.value != null
              ? Image.memory(
                  image!.value!,
                  fit: BoxFit.cover,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  errorBuilder: (_, _, _) => fallback(),
                  excludeFromSemantics: true,
                )
              : fallback(),
        ),
      ),
    );
  }
}

class OwnerCompletion extends StatelessWidget {
  const OwnerCompletion({super.key, required this.profile});
  final OwnerProfile profile;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: AppSpacing.lg),
      Text(
        'Profile ${profile.completed == profile.total ? 'complete' : '${(profile.completion * 100).round()}% complete'}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: AppSpacing.sm),
      LinearProgressIndicator(
        value: profile.completion,
        semanticsLabel: 'Profile completion',
        semanticsValue:
            '${profile.completed} of ${profile.total} saved details',
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '${profile.completed} of ${profile.total} details saved · Photo optional',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class OwnerDrawerHeader extends ConsumerWidget {
  const OwnerDrawerHeader({super.key, required this.openProfile});
  final VoidCallback openProfile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(ownerSignupPhotoRecoveryProvider);
    final value = ref.watch(ownerProfileProvider);
    final profile = currentOwnerProfile(ref);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionAuthenticated ? session.identity.user : null;
    final name = profile?.name.isNotEmpty == true
        ? profile!.name
        : user?.displayName ?? 'Gym administrator';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SoftPanel(
        glass: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                OwnerPhoto(profile: profile, name: name),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR WORKSPACE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        profile?.gymName ?? 'Gym administrator',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (profile != null)
              OwnerCompletion(profile: profile)
            else if (value.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.lg),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Loading owner profile',
                ),
              ),
            if (value.hasError && profile == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  'Profile details unavailable',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (recovery.hasError)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Photo needs attention · Open profile to retry',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: openProfile,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Manage profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerAccountSection extends ConsumerWidget {
  const OwnerAccountSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(ownerProfileProvider);
    final profile = currentOwnerProfile(ref);
    return ProfileSection(
      title: 'Owner profile',
      icon: Icons.person_outline,
      children: [
        if (profile != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OwnerPhoto(profile: profile, name: profile.name, size: 96),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          IconLabel(profile.email, icon: Icons.email_outlined),
          const SizedBox(height: AppSpacing.sm),
          IconLabel(profile.gymName, icon: Icons.fitness_center_outlined),
          if (profile.phone.isNotEmpty)
            IconLabel(profile.phone, icon: Icons.phone_outlined),
          OwnerCompletion(profile: profile),
        ] else if (value.isLoading)
          const LinearProgressIndicator(semanticsLabel: 'Loading owner profile')
        else
          Text(
            value.error is OwnerProfileFailure
                ? (value.error as OwnerProfileFailure).message
                : 'Profile details are unavailable. Please retry.',
          ),
        const SizedBox(height: AppSpacing.lg),
        if (profile != null)
          FilledButton.icon(
            onPressed: () => context.push(AppRoutes.ownerProfile),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit owner profile'),
          )
        else
          OutlinedButton(
            onPressed: () => ref.invalidate(ownerProfileProvider),
            child: const Text('Retry profile'),
          ),
      ],
    );
  }
}
