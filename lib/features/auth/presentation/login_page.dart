import 'package:flutter/material.dart';
import '../../account_privacy/privacy_support_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/iron_hero.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/motion.dart';

import '../data/auth_failure.dart';
import '../models/session_state.dart';
import '../providers/session_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.registrationSucceeded = false});
  final bool registrationSucceeded;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || ref.read(sessionControllerProvider) is SessionLoading) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(email: _email.text.trim(), password: _password.text);
      if (mounted) TextInput.finishAutofillContext();
    } on AuthFailure {
      // The controller publishes the typed, user-safe error below.
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final busy = _submitting || session is SessionLoading;
    final error = session is SessionError ? session.failure.message : null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IronHero(
                    title: 'Back in control.',
                    eyebrow: 'MuscleDesk',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Rise.staggered(
                    index: 3,
                    child: Text(
                      'Sign in to your account',
                      style: AppType.body.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Rise.staggered(
                    index: 4,
                    child: Glass(
                      radius: AppRadii.xxl,
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      shadow: AppShadow.card,
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.registrationSucceeded) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: const Text(
                                    'Account and gym created. Sign in to continue.',
                                  ),
                                ),
                              ],
                              if (widget.registrationSucceeded)
                                const SizedBox(height: 16),
                              TextFormField(
                                controller: _email,
                                enabled: !busy,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                autocorrect: false,
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) return 'Enter your email.';
                                  if (!RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(email)) {
                                    return 'Enter a valid email address.';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                enabled: !busy,
                                obscureText: _obscurePassword,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'Enter your password.'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    error,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              PressableScale(
                                enabled: !busy,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.pill,
                                    ),
                                    boxShadow: busy ? null : AppShadow.cta,
                                  ),
                                  child: FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () {
                                            HapticFeedback.lightImpact();
                                            _submit();
                                          },
                                    child: busy
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary,
                                                      semanticsLabel:
                                                          'Signing in',
                                                    ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Text('Signing in…'),
                                            ],
                                          )
                                        : const Text('Login'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              PressableScale(
                                enabled: !busy,
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => context.go(AppRoutes.signup),
                                  child: const Text('Sign Up'),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => context.go(
                                        AppRoutes.passwordRecovery,
                                      ),
                                icon: const Icon(Icons.lock_reset_outlined),
                                label: const Text('Recover access'),
                              ),
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => context.go(AppRoutes.activate),
                                icon: const Icon(Icons.key_outlined),
                                label: const Text('Activate with gym code'),
                              ),
                              PrivacySupportLink(enabled: !busy),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Manage members, memberships and daily collections.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
