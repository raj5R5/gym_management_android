import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/profile_section.dart';
import '../models/member_models.dart';
import '../models/pending_onboarding.dart';
import 'member_photo_models.dart';
import 'member_photo_providers.dart';

String? effectivePhotoUrl(
  WidgetRef ref,
  MemberPhotoTarget target,
  MemberProfile member,
) {
  final receipt = ref.watch(
    memberPhotoReceiptsProvider.select((items) => items[target]),
  );
  return receipt != null && receipt.revision >= member.photoRevision
      ? receipt.url
      : member.photoUrl;
}

/// One authenticated image path for circular avatars, cover crops and viewing.
/// Presentation size never changes the scoped URL/revision provider cache key.
class MemberPhotoAvatar extends ConsumerWidget {
  const MemberPhotoAvatar({super.key, required this.member, this.radius = 29})
    : width = null,
      height = null,
      borderRadius = null,
      fit = BoxFit.cover,
      viewable = false;

  const MemberPhotoAvatar.cover({
    super.key,
    required this.member,
    this.width = double.infinity,
    required double this.height,
    this.borderRadius = BorderRadius.zero,
    this.fit = BoxFit.cover,
    this.viewable = false,
  }) : radius = 29;

  final MemberProfile member;
  final double radius;
  final double? width, height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final bool viewable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String initial(String value) => value.trim().isEmpty
        ? '?'
        : value.trim().characters.first.toUpperCase();
    final initials = Text(
      '${initial(member.firstName)}${initial(member.lastName)}',
      style: TextStyle(
        fontSize: borderRadius == null ? (radius < 29 ? 20 : 23) : 26,
        fontWeight: FontWeight.w700,
      ),
    );
    final fallback = borderRadius == null
        ? CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            child: initials,
          )
        : ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(child: initials),
          );
    final target = memberPhotoTarget(ref, memberId: member.id);
    final url = target == null ? null : effectivePhotoUrl(ref, target, member);
    final image = target == null || url == null
        ? null
        : ref.watch(memberPhotoImageProvider((target: target, url: url)));
    final canView = viewable && target != null && url != null;
    Widget clip(Widget child) => borderRadius == null
        ? ClipOval(child: child)
        : ClipRRect(borderRadius: borderRadius!, child: child);
    final portrait = SizedBox(
      width: width ?? radius * 2,
      height: height ?? radius * 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pixels =
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil()
                  .clamp(1, 1600);
          return clip(
            Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                if (image?.asData?.value case final bytes?)
                  Image.memory(
                    bytes,
                    fit: fit,
                    cacheWidth: pixels,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => fallback,
                  ),
                if (image?.isLoading == true)
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Loading member photo',
                        ),
                      ),
                    ),
                  ),
                if (canView)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.open_in_full, size: 16),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (!canView) {
      return Semantics(
        label: url == null
            ? 'Initials for ${member.name}'
            : 'Profile photo for ${member.name}',
        image: true,
        child: ExcludeSemantics(child: portrait),
      );
    }
    return Semantics(
      button: true,
      label: 'View profile photo for ${member.name}',
      child: Tooltip(
        message: 'View larger photo',
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _MemberPhotoViewer(member: member, target: target),
          ),
          child: ExcludeSemantics(child: portrait),
        ),
      ),
    );
  }
}

/// Read-only viewer: the same authenticated bytes and revision are shared with
/// the thumbnail. An account/gym change removes the old member from this dialog.
class _MemberPhotoViewer extends ConsumerWidget {
  const _MemberPhotoViewer({required this.member, required this.target});
  final MemberProfile member;
  final MemberPhotoTarget target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = memberPhotoTarget(ref, memberId: member.id);
    final sameScope = current == target;
    final url = sameScope ? effectivePhotoUrl(ref, target, member) : null;
    final image = url == null
        ? null
        : ref.watch(memberPhotoImageProvider((target: target, url: url)));
    final height = (MediaQuery.sizeOf(context).height * .5).clamp(128.0, 480.0);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profile photo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close photo',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!sameScope)
                        const Text(
                          'The account or gym changed. Close this photo and reopen the member.',
                        )
                      else ...[
                        MemberPhotoAvatar.cover(
                          member: member,
                          height: height,
                          borderRadius: BorderRadius.circular(12),
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          member.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (image?.hasError == true) ...[
                          const SizedBox(height: 8),
                          const Text('The photo could not be loaded.'),
                          TextButton(
                            onPressed: () => ref.invalidate(
                              memberPhotoImageProvider((
                                target: target,
                                url: url!,
                              )),
                            ),
                            child: const Text('Retry photo'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberPhotoEditor extends ConsumerWidget {
  const MemberPhotoEditor({
    super.key,
    required this.target,
    this.member,
    this.enabled = true,
  });
  final MemberPhotoTarget target;
  final MemberProfile? member;
  final bool enabled;
  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('The member will use their initials avatar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove photo'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(memberPhotoControllerProvider(target).notifier).remove();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(memberPhotoControllerProvider(target));
    final controller = ref.read(memberPhotoControllerProvider(target).notifier);
    final state = value.asData?.value;
    final pending = state?.pending;
    final busy = state?.busy ?? value.isLoading;
    final receipt = ref.watch(
      memberPhotoReceiptsProvider.select((items) => items[target]),
    );
    final currentUrl = member != null
        ? effectivePhotoUrl(ref, target, member!)
        : receipt?.url;
    final currentBytes = member == null && currentUrl != null
        ? ref
              .watch(
                memberPhotoImageProvider((target: target, url: currentUrl)),
              )
              .asData
              ?.value
        : null;
    final hasPhoto = currentUrl != null;
    final canChange = enabled && !busy && pending?.attempted != true;
    return ProfileSection(
      title: 'Profile photo',
      icon: Icons.add_a_photo_outlined,
      subtitle: target.memberId == null
          ? 'Optional · Uploads after registration is confirmed'
          : 'Optional · Photo saves separately from member details',
      children: [
        if (value.hasError) ...[
          Text(
            value.error is MemberPhotoFailure
                ? (value.error! as MemberPhotoFailure).message
                : 'Photo controls are unavailable. Member details and registration are unchanged.',
          ),
          TextButton(
            onPressed: enabled
                ? () => ref.invalidate(memberPhotoControllerProvider(target))
                : null,
            child: const Text('Retry photo controls'),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: state?.preview != null
                      ? Image.memory(
                          state!.preview!,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (80 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : currentBytes != null
                      ? Image.memory(
                          currentBytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Center(child: Icon(Icons.person_outline)),
                        )
                      : member != null
                      ? Center(
                          child: MemberPhotoAvatar(member: member!, radius: 32),
                        )
                      : ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.person_outline, size: 32),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending?.remove == true
                          ? 'Removal saved · Retry to confirm'
                          : pending != null
                          ? pending.attempted
                                ? 'Saved photo · Outcome needs verification'
                                : 'Selected photo · Preview'
                          : hasPhoto
                          ? 'Current member photo'
                          : 'Initials avatar',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPEG, PNG or WebP · Up to 5 MB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (target.memberId == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Your selection is saved on this device. You can finish the upload later if needed.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (busy) ...[
            LinearProgressIndicator(
              value: state?.progress == 1 ? null : state?.progress,
              semanticsLabel: 'Saving member photo',
            ),
            const SizedBox(height: 8),
            Text(
              state?.progress == 1
                  ? 'Saving photo…'
                  : state?.progress != null
                  ? 'Uploading photo · ${(state!.progress! * 100).round()}%'
                  : 'Preparing photo…',
            ),
          ],
          if (state?.error case final error?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                error.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (state?.success case final success?) ...[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(success)),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: canChange
                    ? () => controller.choose(ImageSource.gallery)
                    : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
              TextButton.icon(
                onPressed: canChange
                    ? () => controller.choose(ImageSource.camera)
                    : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              if (pending != null &&
                  (!pending.attempted || state?.error?.code == 'PHOTO_CHANGED'))
                TextButton(
                  onPressed: enabled && !busy ? controller.cancel : null,
                  child: const Text('Cancel selection'),
                ),
              if (pending != null && target.memberId != null)
                FilledButton.icon(
                  onPressed: enabled && !busy ? controller.upload : null,
                  icon: Icon(
                    pending.remove
                        ? Icons.delete_outline
                        : Icons.cloud_upload_outlined,
                  ),
                  label: Text(
                    pending.attempted ? 'Retry saved photo' : 'Upload photo',
                  ),
                ),
              if (hasPhoto && pending == null)
                TextButton.icon(
                  onPressed: enabled && !busy
                      ? () => _remove(context, ref)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove photo'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

typedef RegistrationPhotoRequest = ({
  OnboardingScope scope,
  String key,
  String? memberId,
});
final registrationPhotoRecoveryProvider = FutureProvider.autoDispose
    .family<MemberPhotoTarget?, RegistrationPhotoRequest>((ref, request) async {
      final service = ref.watch(memberPhotoServiceProvider);
      final target = MemberPhotoTarget(
        request.scope,
        memberId: request.memberId,
      );
      if (request.memberId != null) {
        await service.bindConfirmed(
          request.scope,
          request.key,
          request.memberId!,
        );
      }
      return await service.pending(target) == null ? null : target;
    }, retry: (_, _) => null);

class RegistrationPhotoRecovery extends ConsumerStatefulWidget {
  const RegistrationPhotoRecovery({
    super.key,
    required this.scope,
    required this.operationKey,
    this.memberId,
  });
  final OnboardingScope scope;
  final String operationKey;
  final String? memberId;
  @override
  ConsumerState<RegistrationPhotoRecovery> createState() =>
      _RegistrationPhotoRecoveryState();
}

class _RegistrationPhotoRecoveryState
    extends ConsumerState<RegistrationPhotoRecovery> {
  bool _started = false;
  @override
  Widget build(BuildContext context) {
    final request = (
      scope: widget.scope,
      key: widget.operationKey,
      memberId: widget.memberId,
    );
    final state = ref.watch(registrationPhotoRecoveryProvider(request));
    if (state.isLoading) return const SizedBox.shrink();
    if (state.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The optional photo selection could not be recovered. The saved registration remains available.',
          ),
          TextButton(
            onPressed: () =>
                ref.invalidate(registrationPhotoRecoveryProvider(request)),
            child: const Text('Retry photo recovery'),
          ),
        ],
      );
    }
    final target = state.asData?.value;
    if (target != null && widget.memberId != null && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final pending = await ref.read(
            memberPhotoControllerProvider(target).future,
          );
          if (mounted &&
              pending.pending != null &&
              !pending.pending!.attempted) {
            await ref
                .read(memberPhotoControllerProvider(target).notifier)
                .upload();
          }
        } catch (_) {
          // The editor exposes the provider's loading/recovery error below.
          if (mounted) setState(() {});
        }
      });
    }
    return target == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 16),
            child: MemberPhotoEditor(target: target),
          );
  }
}

/// Existing Member Details stays compact when no optional photo needs recovery.
class MemberPhotoRecoveryPanel extends ConsumerWidget {
  const MemberPhotoRecoveryPanel({
    super.key,
    required this.member,
    this.enabled = true,
  });
  final MemberProfile member;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = memberPhotoTarget(ref, memberId: member.id);
    if (target == null) return const SizedBox.shrink();
    final state = ref.watch(memberPhotoControllerProvider(target));
    if (state.hasError) {
      return TextButton(
        onPressed: enabled
            ? () => ref.invalidate(memberPhotoControllerProvider(target))
            : null,
        child: const Text('Retry saved photo recovery'),
      );
    }
    return state.asData?.value.pending == null
        ? const SizedBox.shrink()
        : MemberPhotoEditor(target: target, member: member, enabled: enabled);
  }
}
