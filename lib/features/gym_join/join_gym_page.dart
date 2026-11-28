import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/page_section.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/session_controller.dart';
import 'gym_join.dart';

/// For someone signed in who belongs to no gym yet: ask a gym to let them
/// join with its code, see their requests, or check again after the gym
/// adds their number.
class JoinGymPage extends ConsumerStatefulWidget {
  const JoinGymPage({super.key});
  @override
  ConsumerState<JoinGymPage> createState() => _JoinGymPageState();
}

class _JoinGymPageState extends ConsumerState<JoinGymPage> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  JoinRole _role = JoinRole.member;
  String? _gymName, _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    if (session is SessionAuthenticated) {
      _name.text = session.identity.user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(GymJoinRepository) action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(gymJoinRepositoryProvider));
    } on GymJoinFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _lookup() => _run((repository) async {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) {
      setState(() => _error = 'A gym code has 6 letters and numbers.');
      return;
    }
    final name = await repository.lookup(code);
    if (mounted) setState(() => _gymName = name);
  });

  Future<void> _ask() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name so the gym knows who you are.');
      return;
    }
    await _run((repository) async {
      final outcome = await repository.ask(
        code: _code.text,
        role: _role,
        name: _name.text,
      );
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      switch (outcome) {
        case JoinLinked(:final gymName):
          _snack('You are in $gymName.');
          // The new gym access arrives with the refreshed session.
          await container
              .read(sessionControllerProvider.notifier)
              .refreshSession();
        case JoinPending(:final request):
          _snack('Request sent to ${request.gymName ?? 'the gym'}.');
          setState(() {
            _gymName = null;
            _code.clear();
          });
          container.invalidate(myJoinRequestsProvider);
      }
    });
  }

  Future<void> _checkAgain() => _run((repository) async {
    final linked = await repository.checkAgain();
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    if (linked == 0) {
      _snack('No gym has added your number yet.');
      container.invalidate(myJoinRequestsProvider);
      return;
    }
    await container.read(sessionControllerProvider.notifier).refreshSession();
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = ref.watch(myJoinRequestsProvider);
    // An approved request means access is waiting in a fresh session.
    ref.listen(myJoinRequestsProvider, (_, next) {
      final rows = next.asData?.value ?? const <JoinRequest>[];
      if (rows.any((row) => row.status == JoinStatus.approved)) {
        ref.read(sessionControllerProvider.notifier).refreshSession();
      }
    });
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myJoinRequestsProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Join your gym',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref
                              .read(sessionControllerProvider.notifier)
                              .logout(),
                    child: const Text('Logout'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your number is not linked to a gym yet. If your gym added you, '
                'tap Check again. Otherwise ask the gym for its code.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('check-again'),
                onPressed: _busy ? null : _checkAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
              PageSection(
                title: 'Ask a gym to let you in',
                children: [
                  TextField(
                    key: const ValueKey('gym-code'),
                    controller: _code,
                    enabled: !_busy && _gymName == null,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 4,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Gym code',
                      helperText:
                          'Ask at the front desk, or read it from the gym QR.',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                  if (_gymName != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Join $_gymName as',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<JoinRole>(
                      segments: [
                        for (final role in JoinRole.values)
                          ButtonSegment(value: role, label: Text(role.label)),
                      ],
                      selected: {_role},
                      onSelectionChanged: _busy
                          ? null
                          : (value) => setState(() => _role = value.first),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('join-name'),
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      if (_gymName != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _gymName = null),
                          child: const Text('Change code'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : (_gymName == null ? _lookup : _ask),
                        child: Text(
                          _gymName == null ? 'Find gym' : 'Send request',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              PageSection(
                title: 'Your requests',
                children: [
                  switch (requests) {
                    AsyncData(:final value) when value.isEmpty => Text(
                      'No requests yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    AsyncData(:final value) => Column(
                      children: [for (final row in value) _RequestRow(row)],
                    ),
                    AsyncError() => Text(
                      'Could not load your requests. Pull down to try again.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    _ => const LinearProgressIndicator(),
                  },
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends ConsumerWidget {
  const _RequestRow(this.request);
  final JoinRequest request;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = switch (request.status) {
      JoinStatus.pending => 'Waiting for the owner',
      JoinStatus.approved => 'Approved',
      JoinStatus.rejected =>
        request.reason == null
            ? 'Not accepted'
            : 'Not accepted: ${request.reason}',
      JoinStatus.cancelled => 'Cancelled',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        request.status == JoinStatus.pending
            ? Icons.hourglass_top_outlined
            : request.status == JoinStatus.approved
            ? Icons.check_circle_outline
            : Icons.cancel_outlined,
      ),
      title: Text('${request.gymName ?? 'Gym'} · ${request.role.label}'),
      subtitle: Text(
        status,
        style: request.status == JoinStatus.rejected
            ? TextStyle(color: theme.colorScheme.error)
            : null,
      ),
      trailing: request.status == JoinStatus.pending
          ? TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(gymJoinRepositoryProvider).cancel(request.id);
                  ref.invalidate(myJoinRequestsProvider);
                } on GymJoinFailure catch (failure) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(failure.message)),
                  );
                }
              },
              child: const Text('Cancel'),
            )
          : null,
    );
  }
}
