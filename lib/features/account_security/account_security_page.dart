import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';
import '../auth/models/owner_registration.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/session_controller.dart';
import 'account_security.dart';

/// Email verification, password and signed-in devices for the owner.
class AccountSecurityPage extends ConsumerWidget {
  const AccountSecurityPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionAuthenticated ? session.identity.user : null;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.more),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                'Sign-in & security',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        if (user != null) ...[
          PageSection(
            title: 'Email',
            top: AppSpacing.lg,
            children: [
              Text(user.email, style: theme.textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.sm),
              if (user.emailVerified)
                const Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 18),
                    SizedBox(width: AppSpacing.sm),
                    Text('Verified'),
                  ],
                )
              else
                const _VerifyEmail(),
            ],
          ),
          const PageSection(title: 'Password', children: [_ChangePassword()]),
          const PageSection(title: 'Signed-in devices', children: [_Devices()]),
        ],
      ],
    );
  }
}

class _VerifyEmail extends ConsumerStatefulWidget {
  const _VerifyEmail();
  @override
  ConsumerState<_VerifyEmail> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends ConsumerState<_VerifyEmail> {
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(AccountSecurityRepository) action, {
    bool sending = false,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(container.read(accountSecurityRepositoryProvider));
      if (!mounted) return;
      if (sending) {
        setState(() => _sent = true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email verified.')));
        // Reload the account so "Verified" shows everywhere.
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
      }
    } on AccountSecurityFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _sent
              ? 'We emailed you a 6-digit code. It expires in 15 minutes.'
              : 'Not verified yet. Verifying makes sure password recovery reaches you.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: _sent ? null : AppPalette.amber,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_sent) ...[
          TextField(
            key: const ValueKey('verification-code'),
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Code from the email',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    if (_code.text.length != 6) {
                      setState(() => _error = 'Enter the 6-digit code.');
                      return;
                    }
                    _run((repo) => repo.confirmVerification(_code.text));
                  },
            child: const Text('Verify email'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run((repo) => repo.sendVerification(), sending: true),
            child: const Text('Send a new code'),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run((repo) => repo.sendVerification(), sending: true),
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Send verification code'),
          ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.accentLight,
            ),
          ),
        ],
      ],
    );
  }
}

class _ChangePassword extends ConsumerStatefulWidget {
  const _ChangePassword();
  @override
  ConsumerState<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends ConsumerState<_ChangePassword> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _open = false, _busy = false, _hidden = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ended = await container
          .read(accountSecurityRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      container.invalidate(signedInDevicesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ended == 0
                ? 'Password changed.'
                : 'Password changed. $ended other ${ended == 1 ? 'device was' : 'devices were'} signed out.',
          ),
        ),
      );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() => _open = false);
    } on AccountSecurityFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_open) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _open = true),
          icon: const Icon(Icons.lock_reset),
          label: const Text('Change password'),
        ),
      );
    }
    InputDecoration field(String label, {String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show passwords' : 'Hide passwords',
        onPressed: () => setState(() => _hidden = !_hidden),
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off),
      ),
    );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('current-password'),
            controller: _current,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.password],
            decoration: field('Current password'),
            validator: (value) =>
                (value ?? '').isEmpty ? 'Enter your current password.' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('new-password'),
            controller: _next,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.newPassword],
            decoration: field('New password'),
            validator: ownerPasswordError,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('confirm-password'),
            controller: _confirm,
            obscureText: _hidden,
            decoration: field('Confirm new password'),
            validator: (value) =>
                value != _next.text ? 'Passwords must match.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Other devices will be signed out. This phone stays signed in.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.accentLight,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save new password'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _open = false),
            child: const Text('Keep current password'),
          ),
        ],
      ),
    );
  }
}

class _Devices extends ConsumerWidget {
  const _Devices();

  Future<void> _signOutOthers(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out other devices?',
      message: 'They will need your password to sign in again.',
      keepLabel: 'Keep signed in',
      confirmLabel: 'Sign out others',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ended = await container
          .read(accountSecurityRepositoryProvider)
          .signOutOthers();
      container.invalidate(signedInDevicesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$ended other ${ended == 1 ? 'device' : 'devices'} signed out.',
          ),
        ),
      );
    } on AccountSecurityFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final state = ref.watch(signedInDevicesProvider);
    final rows = state.asData?.value;
    if (rows == null) {
      return state.hasError
          ? Text(
              state.error is AccountSecurityFailure
                  ? (state.error! as AccountSecurityFailure).message
                  : 'Devices could not be loaded.',
            )
          : const LinearProgressIndicator(minHeight: 2);
    }
    final others = rows.where((row) => !row.current).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeparatedRows(
          indent: 40,
          children: [
            for (final row in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row.clientType == 'web'
                      ? Icons.computer_outlined
                      : Icons.phone_android,
                ),
                title: Text(
                  row.current
                      ? 'This phone'
                      : row.clientType == 'web'
                      ? 'Browser'
                      : 'Phone',
                ),
                subtitle: Text(
                  'Last used ${dates.formatMediumDate(row.lastUsedAt)} · '
                  '${TimeOfDay.fromDateTime(row.lastUsedAt).format(context)}',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (others > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.accentLight,
              ),
              onPressed: () => _signOutOthers(context, ref),
              icon: const Icon(Icons.logout),
              label: Text(
                'Sign out $others other ${others == 1 ? 'device' : 'devices'}',
              ),
            ),
          )
        else
          Text(
            'Only this phone is signed in.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
