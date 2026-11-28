import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../notifications/notifications.dart';
import 'gym_join.dart';

/// The owner's gym code to share, and people asking to join.
class JoinRequestsPage extends ConsumerWidget {
  const JoinRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final code = ref.watch(gymJoinCodeProvider);
    final pending = ref.watch(pendingJoinRequestsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pendingJoinRequestsProvider);
        ref.invalidate(gymJoinCodeProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.more),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text('Join requests', style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          PageSection(
            title: 'Your gym code',
            top: AppSpacing.lg,
            children: [
              switch (code) {
                AsyncData(:final value?) => _GymCode(
                  code: value.code,
                  gymName: value.gymName,
                ),
                AsyncError() => Text(
                  'Could not load the gym code. Pull down to try again.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                _ => const LinearProgressIndicator(),
              },
            ],
          ),
          PageSection(
            title: 'Waiting for you',
            children: [
              switch (pending) {
                AsyncData(:final value) when value.isEmpty => Text(
                  'No one is waiting. People who enter your gym code in the app show up here.',
                  style: theme.textTheme.bodyMedium,
                ),
                AsyncData(:final value) => SeparatedRows(
                  indent: 40,
                  children: [for (final row in value) _RequestTile(row)],
                ),
                AsyncError() => Text(
                  'Could not load requests. Pull down to try again.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                _ => const LinearProgressIndicator(),
              },
            ],
          ),
        ],
      ),
    );
  }
}

class _GymCode extends StatelessWidget {
  const _GymCode({required this.code, required this.gymName});
  final String code, gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          code,
          key: const ValueKey('gym-join-code'),
          style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 8),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Members and trainers enter this in the app to ask to join $gymName. '
          'You approve each one here.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      'Join $gymName on MuscleDesk: sign in with your phone, '
                      'then enter the gym code $code.',
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite message copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy invite message'),
          ),
        ),
      ],
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile(this.request);
  final JoinRequest request;
  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _busy) return;
    final request = widget.request;
    String? reason;
    if (approve) {
      final ok = await showConfirmDialog(
        context,
        title: 'Add ${request.name}?',
        message: request.role == JoinRole.member
            ? 'They become a member of your gym and can see their plan and visits. '
                  'Add a plan for them from their member page.'
            : 'They become a trainer in your gym and can see their clients.',
        confirmLabel: 'Approve',
        keepLabel: 'Not now',
      );
      if (!ok) return;
    } else {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectDialog(),
      );
      if (reason == null) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final repository = container.read(gymJoinRepositoryProvider);
      if (approve) {
        await repository.approve(gym.gymId, request.id);
      } else {
        await repository.reject(gym.gymId, request.id, reason: reason);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '${request.name} added.'
                : 'Request from ${request.name} declined.',
          ),
        ),
      );
      container
        ..invalidate(pendingJoinRequestsProvider)
        ..invalidate(notificationFeedProvider)
        ..invalidate(dashboardProvider);
    } on GymJoinFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final dates = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            request.role == JoinRole.member
                ? Icons.person_add_alt_outlined
                : Icons.sports_gymnastics,
          ),
          title: Text(request.name),
          subtitle: Text(
            '${request.role.label} · ${request.phone} · '
            '${dates.formatShortMonthDay(request.createdAt)}',
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _decide(false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _decide(true),
              child: const Text('Approve'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Decline this request?'),
    content: TextField(
      controller: _reason,
      maxLength: 200,
      decoration: const InputDecoration(
        labelText: 'Reason (optional)',
        helperText: 'They see this in the app.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep it'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
        child: const Text('Decline'),
      ),
    ],
  );
}
