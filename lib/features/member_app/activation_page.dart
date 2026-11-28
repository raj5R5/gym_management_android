import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/profile_section.dart';
import '../auth/models/owner_registration.dart';

class ActivationFailure implements Exception {
  const ActivationFailure(this.message);
  final String message;
}

/// Sets the member's first password with the code their gym sent.
class ActivationRepository {
  ActivationRepository(this._client);
  final Dio _client;

  Future<void> activate(
    String code,
    String password,
    CancelToken cancel,
  ) async {
    try {
      final response = await _client.post<dynamic>(
        'account/activate',
        data: {'token': code, 'password': password},
        cancelToken: cancel,
        options: Options(
          followRedirects: false,
          headers: {'Authorization': null, 'Cookie': null},
          extra: {'authRequired': false},
        ),
      );
      final body = response.data;
      if (body is! Map || body['success'] != true) {
        throw const ActivationFailure('Activation could not be confirmed.');
      }
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw ActivationFailure(switch (code) {
        'INVALID_ACTIVATION_CREDENTIAL' =>
          'This code is wrong, used or expired. Ask your gym for a new one.',
        'VALIDATION_ERROR' =>
          'Check the code, and choose a less predictable password.',
        'RATE_LIMITED' || 'TOO_MANY_REQUESTS' =>
          'Too many tries. Wait a few minutes and try again.',
        _ =>
          error.response == null
              ? 'No connection. Check your internet and try again.'
              : 'Activation failed. Try again.',
      });
    }
  }
}

final activationRepositoryProvider = Provider<ActivationRepository>(
  (ref) => ActivationRepository(ref.watch(apiClientProvider)),
);

/// Accepts the code alone, or a whole pasted WhatsApp message containing it.
String? extractActivationCode(String text) => RegExp(
  r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])',
).firstMatch(text.trim())?.group(0);

class ActivationPage extends ConsumerStatefulWidget {
  const ActivationPage({super.key});
  @override
  ConsumerState<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends ConsumerState<ActivationPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _cancel = CancelToken();
  bool _busy = false, _done = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    _cancel.cancel('Activation page closed');
    for (final controller in [_code, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final code = extractActivationCode(text);
    if (!mounted) return;
    if (code == null) {
      setState(() => _error = 'No code found in what you copied.');
    } else {
      setState(() {
        _code.text = code;
        _error = null;
      });
    }
  }

  Future<void> _activate() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(activationRepositoryProvider)
          .activate(
            extractActivationCode(_code.text)!,
            _password.text,
            _cancel,
          );
      if (mounted) setState(() => _done = true);
    } on ActivationFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Opened with go(), so there is nothing to pop: Back returns to sign-in
    // instead of closing the app.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) context.go(AppRoutes.login);
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Activate your account'),
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
            if (_done)
              ProfileSection(
                title: 'You are all set',
                icon: Icons.verified_user_outlined,
                children: [
                  const Text(
                    'Your password is saved. Sign in with your email and new password.',
                  ),
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text('Go to sign in'),
                  ),
                ],
              )
            else
              Form(
                key: _form,
                child: ProfileSection(
                  title: 'Got a code from your gym?',
                  icon: Icons.key_outlined,
                  children: [
                    const Text(
                      'Copy the WhatsApp message from your gym, tap Paste, then '
                      'choose your password.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('activationCode'),
                      controller: _code,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) =>
                          extractActivationCode(value ?? '') == null
                          ? 'Paste the full code your gym sent.'
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Activation code',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: TextButton(
                          onPressed: _busy ? null : _paste,
                          child: const Text('Paste'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('activationPassword'),
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _hide,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: ownerPasswordError,
                      decoration: InputDecoration(
                        labelText: 'Choose a password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _hide = !_hide),
                          icon: Icon(
                            _hide
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('activationConfirm'),
                      controller: _confirmation,
                      enabled: !_busy,
                      obscureText: _hide,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: (value) => value != _password.text
                          ? 'Passwords do not match.'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Repeat password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: _busy ? null : _activate,
                      child: Text(_busy ? 'Activating…' : 'Activate'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
