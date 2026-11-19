import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/trainer_failure.dart';
import '../models/trainer_models.dart';
import '../../../shared/widgets/page_section.dart';

/// Creates a trainer login and links it to the trainer's profile.
class TrainerAccessRepository {
  TrainerAccessRepository(this._client);
  final Dio _client;

  Future<void> giveAccess(
    String gymId,
    TrainerProfile trainer, {
    required String email,
    required String password,
  }) async {
    try {
      final body = (await _client.post<dynamic>(
        'gyms/$gymId/staff',
        data: {
          'email': email,
          'displayName': trainer.name,
          'role': 'trainer',
          'password': password,
          'trainerId': trainer.id,
        },
      )).data;
      if (body is! Map || body['success'] != true) {
        throw const TrainerFailure('Unexpected response.');
      }
    } on DioException catch (error) {
      throw TrainerFailure.fromDio(error);
    }
  }
}

final trainerAccessRepositoryProvider = Provider<TrainerAccessRepository>(
  (ref) => TrainerAccessRepository(ref.watch(authenticatedApiClientProvider)),
);

/// Trainer profile card: app access status, or a button to grant it.
class TrainerAppAccessCard extends ConsumerWidget {
  const TrainerAppAccessCard({
    super.key,
    required this.gymId,
    required this.trainer,
    required this.onGranted,
  });
  final String gymId;
  final TrainerProfile trainer;
  final VoidCallback onGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Trainer app', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            trainer.hasAppAccess
                ? '${trainer.firstName} can sign in to see PT clients and log sessions. '
                      'Prices and payments stay hidden.'
                : 'Let ${trainer.firstName} sign in to see PT clients and log '
                      'sessions. Prices and payments stay hidden.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (trainer.hasAppAccess)
            const Row(
              children: [
                Icon(Icons.verified_outlined, size: 18),
                SizedBox(width: AppSpacing.xs),
                Text('App access on'),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: trainer.status != TrainerStatus.active
                  ? null
                  : () async {
                      final granted = await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            _GrantDialog(gymId: gymId, trainer: trainer),
                      );
                      if (granted == true) onGranted();
                    },
              icon: const Icon(Icons.key_outlined),
              label: const Text('Give app access'),
            ),
        ],
      ),
    );
  }
}

class _GrantDialog extends ConsumerStatefulWidget {
  const _GrantDialog({required this.gymId, required this.trainer});
  final String gymId;
  final TrainerProfile trainer;
  @override
  ConsumerState<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends ConsumerState<_GrantDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true, _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(trainerAccessRepositoryProvider)
          .giveAccess(
            widget.gymId,
            widget.trainer,
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on TrainerFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('App access for ${widget.trainer.firstName}'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('trainer-access-email'),
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Their email'),
              validator: (value) =>
                  RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch((value ?? '').trim())
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('trainer-access-password'),
              controller: _password,
              enabled: !_saving,
              obscureText: _hidden,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Temporary password',
                helperText:
                    '15+ characters, not a common phrase. Share it privately.',
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value ?? '').length < 15
                  ? 'Use at least 15 characters'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Give access'),
      ),
    ],
  );
}
