import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../account_privacy/privacy_support_page.dart';
import '../data/password_recovery_repository.dart';
import '../models/owner_registration.dart';

class PasswordRecoveryPage extends ConsumerStatefulWidget {
  const PasswordRecoveryPage({super.key});
  @override
  ConsumerState<PasswordRecoveryPage> createState() =>
      _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends ConsumerState<PasswordRecoveryPage> {
  final _requestForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _cancel = CancelToken();
  bool _busy = false, _accepted = false, _changed = false, _hidePassword = true;
  String? _error;

  Future<void> _send(bool complete) async {
    if (_busy ||
        !(complete ? _resetForm : _requestForm).currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(passwordRecoveryRepositoryProvider);
      if (complete) {
        await repository.complete(_token.text, _password.text, _cancel);
      } else {
        await repository.request(_email.text, _cancel);
      }
      if (!mounted) return;
      setState(() {
        if (complete) {
          _changed = true;
          _token.clear();
          _password.clear();
          _confirmation.clear();
        } else {
          _accepted = true;
        }
      });
    } on PasswordRecoveryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Recovery could not be confirmed. Try signing in before repeating a password change.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancel.cancel('Recovery page closed');
    for (final controller in [_email, _token, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Recover access'),
        leading: IconButton(
          tooltip: 'Back to login',
          onPressed: _busy ? null : () => context.go(AppRoutes.login),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Use your registered email. Never send your password or recovery code to support.',
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_changed)
              ProfileSection(
                title: 'Password changed',
                icon: Icons.verified_user_outlined,
                children: [
                  const Text(
                    'The server confirmed your password change. Previous sessions have been revoked. Sign in with your new password.',
                  ),
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text('Back to login'),
                  ),
                ],
              )
            else ...[
              Form(
                key: _requestForm,
                child: ProfileSection(
                  title: '1 · Request a recovery code',
                  icon: Icons.mark_email_read_outlined,
                  children: [
                    TextFormField(
                      key: const ValueKey('recoveryEmail'),
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: ownerEmailError,
                      decoration: const InputDecoration(
                        labelText: 'Registered email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _send(false),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Request code'),
                    ),
                    if (_accepted)
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Request accepted. If this address has an eligible account, recovery instructions will be sent. This does not confirm delivery. Check spam or contact support if nothing arrives.',
                        ),
                      ),
                  ],
                ),
              ),
              Form(
                key: _resetForm,
                child: ProfileSection(
                  title: '2 · Set a new password',
                  icon: Icons.lock_reset_outlined,
                  children: [
                    TextFormField(
                      key: const ValueKey('recoveryToken'),
                      controller: _token,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) =>
                          RegExp(
                            r'^[A-Za-z0-9_-]{43}$',
                          ).hasMatch((value ?? '').trim())
                          ? null
                          : 'Paste the complete code from your recovery email.',
                      decoration: const InputDecoration(
                        labelText: 'Recovery code',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                    ),
                    TextFormField(
                      key: const ValueKey('recoveryPassword'),
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _hidePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: ownerPasswordError,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText:
                            'Use 15–128 characters; avoid common or repeated patterns.',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    TextFormField(
                      key: const ValueKey('recoveryConfirmation'),
                      controller: _confirmation,
                      enabled: !_busy,
                      obscureText: _hidePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) =>
                          value != null &&
                              value.isNotEmpty &&
                              value == _password.text
                          ? null
                          : 'Passwords must match.',
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _send(true),
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Change password'),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Waiting for recovery confirmation',
                ),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            PrivacySupportLink(enabled: !_busy),
          ],
        ),
      ),
    ),
  );
}
