import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/config/app_config.dart';
import '../../core/config/public_app_info.dart';
import '../../shared/widgets/feedback_notice.dart';
import '../../shared/widgets/field_icon.dart';
import '../../shared/widgets/profile_section.dart';
import '../auth/models/session_state.dart';
import '../auth/providers/session_controller.dart';
import '../account_security/account_security.dart';
import 'account_deletion_repository.dart';
import 'privacy_support_page.dart';

class AccountDeletionPage extends ConsumerStatefulWidget {
  const AccountDeletionPage({super.key});
  @override
  ConsumerState<AccountDeletionPage> createState() =>
      _AccountDeletionPageState();
}

class _AccountDeletionPageState extends ConsumerState<AccountDeletionPage> {
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  CancelToken? _cancel;
  bool _busy = false, _acknowledged = false, _hidden = true;
  // Accounts without a password confirm with a code sent to their phone.
  bool _codeSent = false, _sending = false;

  Future<void> _sendCode() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(accountSecurityRepositoryProvider).sendConfirmCode();
      if (mounted) setState(() => _codeSent = true);
    } on AccountSecurityFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _error;
  @override
  void dispose() {
    _cancel?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(String userId) async {
    if (_busy || !_acknowledged || !_form.currentState!.validate()) return;
    final config = ref.read(appConfigProvider);
    final repository = ref.read(accountDeletionRepositoryProvider);
    final cancel = _cancel = CancelToken();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    bool current() {
      if (!mounted || !identical(config, ref.read(appConfigProvider))) {
        return false;
      }
      final session = ref.read(sessionControllerProvider);
      return session is SessionAuthenticated &&
          session.identity.user.id == userId;
    }

    try {
      final session = ref.read(sessionControllerProvider);
      final phoneCode =
          session is SessionAuthenticated && !session.identity.user.hasPassword;
      await repository.request(
        userId,
        phoneCode ? _password.text.trim() : _password.text,
        cancel,
        phoneCode: phoneCode,
      );
    } on AccountDeletionFailure catch (failure) {
      if (current()) setState(() => _error = failure.message);
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
        // A timed-out POST may have succeeded. GET is authoritative and safe.
        if (current()) ref.invalidate(accountDeletionStatusProvider(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appConfigProvider, (_, _) {
      _cancel?.cancel();
      _password.clear();
      _acknowledged = false;
      _error = null;
    });
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next is! SessionAuthenticated ||
          previous is SessionAuthenticated &&
              previous.identity.user.id != next.identity.user.id) {
        _cancel?.cancel();
        _password.clear();
        _acknowledged = false;
        _error = null;
      }
    });
    final session = ref.watch(sessionControllerProvider);
    final info = ref.watch(publicAppInfoProvider);
    if (session is! SessionAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = session.identity.user;
    final status = ref.watch(accountDeletionStatusProvider(user.id));
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Account deletion'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ProfileSection(
                title: 'Request account deletion',
                icon: Icons.person_remove_outlined,
                children: [
                  Text(
                    user.contact,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'This sends a verified request to delete your app account and associated personal data. A received request is not confirmation that deletion is complete.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'The operator reviews and carries out requests manually. Your account remains usable until then. If you are the only owner of a gym, the operator will email you to confirm whether to close it or hand it to a staff member first. You receive an email when deletion is complete.',
                  ),
                ],
              ),
              if (status.isLoading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Checking deletion request',
                ),
              if (status.hasError)
                FeedbackNotice(
                  message: status.error is AccountDeletionFailure
                      ? (status.error! as AccountDeletionFailure).message
                      : 'The request status is unavailable. Recheck before submitting.',
                  retry: _busy
                      ? null
                      : () => ref.invalidate(
                          accountDeletionStatusProvider(user.id),
                        ),
                ),
              if (status.asData?.value case final DeletionRequest receipt)
                ProfileSection(
                  title: receipt.status == 'completed'
                      ? 'Deletion reported complete'
                      : 'Request received',
                  icon: Icons.receipt_long_outlined,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(switch (receipt.status) {
                        'completed' =>
                          'The server reports that your request is complete. Contact support if your account is still accessible.',
                        'in_review' =>
                          'Your request is under review. Account deletion has not been confirmed.',
                        _ =>
                          'Your request was saved. Account deletion has not been confirmed.',
                      }),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SelectableText('Request reference: ${receipt.id}'),
                    Text(
                      'Requested: ${MaterialLocalizations.of(context).formatMediumDate(receipt.requestedAt.toLocal())}',
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => ref.invalidate(
                              accountDeletionStatusProvider(user.id),
                            ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recheck status'),
                    ),
                  ],
                )
              else if (status.hasValue && !status.isLoading && !status.hasError)
                ProfileSection(
                  title: 'Verify your request',
                  icon: Icons.lock_outline,
                  children: [
                    if (!session.identity.user.hasPassword && !_codeSent)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _busy || _sending ? null : _sendCode,
                          icon: const Icon(Icons.sms_outlined),
                          label: const Text('Send code to my phone'),
                        ),
                      )
                    else if (!session.identity.user.hasPassword)
                      Form(
                        key: _form,
                        child: TextFormField(
                          key: const ValueKey('deletion-code'),
                          controller: _password,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                            labelText: 'Code sent to your phone',
                            prefixIcon: Icon(Icons.sms_outlined),
                          ),
                          validator: (value) =>
                              RegExp(r'^\d{4,8}$').hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter the code from the SMS.',
                        ),
                      )
                    else
                      Form(
                        key: _form,
                        child: TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hidden,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: const FieldIcon('currentPassword'),
                            suffixIcon: IconButton(
                              tooltip: _hidden
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _hidden = !_hidden),
                              icon: Icon(
                                _hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your current password.'
                              : null,
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acknowledged,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _acknowledged = value ?? false),
                      title: const Text(
                        'I want to request deletion of my account and associated personal data.',
                      ),
                    ),
                    FilledButton.icon(
                      style: AppButtonStyles.warning(context),
                      onPressed: _busy || !_acknowledged
                          ? null
                          : () => _submit(user.id),
                      icon: const Icon(Icons.person_remove_outlined),
                      label: Text(
                        _busy ? 'Sending request…' : 'Submit deletion request',
                      ),
                    ),
                  ],
                ),
              if (_error case final message?) FeedbackNotice(message: message),
              PolicyLinkSection(
                title: 'Public deletion process',
                icon: Icons.open_in_new,
                uri: info.deletionUrl,
              ),
              const PrivacySupportLink(),
            ],
          ),
        ),
      ),
    );
  }
}
