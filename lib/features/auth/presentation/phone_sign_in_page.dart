import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/iron_hero.dart';
import '../../../shared/widgets/motion.dart';
import '../../account_privacy/privacy_support_page.dart';
import '../data/auth_failure.dart';
import '../data/phone_auth_repository.dart';
import '../providers/session_controller.dart';

/// Who is signing in. Only changes what a new number is offered: an existing
/// account always opens with its own role.
enum SignInRole {
  owner(
    'Gym owner',
    'Run your gym, members and money',
    Icons.storefront_outlined,
  ),
  member('Member', 'See your plan and mark attendance', Icons.person_outline),
  trainer('Trainer', 'Your clients and sessions', Icons.sports_gymnastics);

  const SignInRole(this.label, this.detail, this.icon);
  final String label, detail;
  final IconData icon;
}

enum _Step { role, phone, code, ownerDetails, yourName }

/// The first screen: choose a role, then sign in or sign up with a phone code.
class PhoneSignInPage extends ConsumerStatefulWidget {
  const PhoneSignInPage({super.key});

  @override
  ConsumerState<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends ConsumerState<PhoneSignInPage> {
  final _phoneForm = GlobalKey<FormState>();
  final _ownerForm = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _gym = TextEditingController();
  final _email = TextEditingController();
  _Step _step = _Step.role;
  SignInRole _role = SignInRole.owner;
  String _digits = '';
  String? _signupToken;
  String? _error;
  bool _busy = false;
  DateTime? _resendAt;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in [_phone, _code, _name, _gym, _email]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PhoneAuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer(Duration wait) {
    _resendAt = DateTime.now().add(wait);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (DateTime.now().isAfter(_resendAt!)) timer.cancel();
    });
  }

  int get _resendSeconds {
    final at = _resendAt;
    if (at == null) return 0;
    final left = at.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left + 1;
  }

  Future<void> _sendCode() async {
    if (!_phoneForm.currentState!.validate()) return;
    final digits = indianMobileDigits(_phone.text)!;
    await _run(() async {
      final sent = await ref
          .read(phoneAuthRepositoryProvider)
          .requestCode(digits);
      _digits = digits;
      _code.clear();
      _startResendTimer(sent.resendAfter);
      if (mounted) _go(_Step.code);
    });
  }

  Future<void> _resend() => _run(() async {
    final sent = await ref
        .read(phoneAuthRepositoryProvider)
        .requestCode(_digits);
    _code.clear();
    _startResendTimer(sent.resendAfter);
  });

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      setState(() => _error = 'Enter the code from the SMS.');
      return;
    }
    await _run(() async {
      final result = await ref
          .read(phoneAuthRepositoryProvider)
          .verify(_digits, code);
      switch (result) {
        case PhoneSignedIn(:final response):
          TextInput.finishAutofillContext();
          await ref
              .read(sessionControllerProvider.notifier)
              .adoptSignIn(response);
        case PhoneNewAccount(:final signupToken):
          _signupToken = signupToken;
          if (mounted) {
            _go(
              _role == SignInRole.owner ? _Step.ownerDetails : _Step.yourName,
            );
          }
      }
    });
  }

  Future<void> _createGym() async {
    if (!_ownerForm.currentState!.validate()) return;
    await _run(() async {
      final response = await ref
          .read(phoneAuthRepositoryProvider)
          .registerOwner(
            signupToken: _signupToken!,
            ownerFullName: _name.text,
            gymName: _gym.text,
            email: _email.text,
          );
      await ref.read(sessionControllerProvider.notifier).adoptSignIn(response);
    });
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_step) {
      _Step.role => ('Welcome.', 'Who is signing in?'),
      _Step.phone => ('Your number.', 'We will text you a code to sign in.'),
      _Step.code => ('Enter the code.', 'Sent by SMS to +91 $_digits'),
      _Step.ownerDetails => ('Set up your gym.', 'Your number is verified.'),
      _Step.yourName => ('Your name.', 'Your number is verified.'),
    };
    return PopScope(
      canPop: _step == _Step.role,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        _go(switch (_step) {
          _Step.code || _Step.yourName || _Step.ownerDetails => _Step.phone,
          _ => _Step.role,
        });
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IronHero(title: title, eyebrow: 'MuscleDesk'),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      key: const ValueKey('phone-sign-in-subtitle'),
                      style: AppType.body.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Rise(
                      key: ValueKey(_step),
                      child: Glass(
                        radius: AppRadii.xxl,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        shadow: AppShadow.card,
                        child: switch (_step) {
                          _Step.role => _roles(),
                          _Step.phone => _phoneStep(),
                          _Step.code => _codeStep(),
                          _Step.ownerDetails => _ownerStep(),
                          _Step.yourName => _nameStep(),
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.go(AppRoutes.login),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Sign in with email and password'),
                    ),
                    PrivacySupportLink(enabled: !_busy),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );

  Widget _primary(String label, VoidCallback onPressed, {String? busyLabel}) =>
      FilledButton(
        onPressed: _busy
            ? null
            : () {
                HapticFeedback.lightImpact();
                onPressed();
              },
        child: _busy
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(busyLabel ?? 'Please wait…'),
                ],
              )
            : Text(label),
      );

  Widget _roles() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final role in SignInRole.values) ...[
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            key: ValueKey('role-${role.name}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(role.icon),
            title: Text(role.label, style: AppType.title),
            subtitle: Text(role.detail),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _role = role;
              _go(_Step.phone);
            },
          ),
        ),
        if (role != SignInRole.values.last) const Divider(height: 1),
      ],
    ],
  );

  Widget _phoneStep() => Form(
    key: _phoneForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signing in as ${_role.label.toLowerCase()}'),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('phone-number'),
          controller: _phone,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
            LengthLimitingTextInputFormatter(16),
          ],
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            prefixText: '+91 ',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: validateIndianMobile,
          onFieldSubmitted: (_) => _sendCode(),
        ),
        _errorText(),
        const SizedBox(height: AppSpacing.xl),
        _primary('Send code', _sendCode, busyLabel: 'Sending…'),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.role),
          child: const Text('Back'),
        ),
      ],
    ),
  );

  Widget _codeStep() {
    final wait = _resendSeconds;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('otp-code'),
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            style: AppType.title.copyWith(letterSpacing: 6),
            decoration: const InputDecoration(
              labelText: 'Code',
              prefixIcon: Icon(Icons.sms_outlined),
            ),
            onSubmitted: (_) => _verify(),
          ),
          _errorText(),
          const SizedBox(height: AppSpacing.xl),
          _primary('Verify', _verify, busyLabel: 'Checking…'),
          const SizedBox(height: AppSpacing.sm),
          // Wraps on narrow screens and with large text.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _go(_Step.phone),
                child: const Text('Change number'),
              ),
              TextButton(
                key: const ValueKey('resend-code'),
                onPressed: _busy || wait > 0 ? null : _resend,
                child: Text(wait > 0 ? 'Resend in ${wait}s' : 'Resend code'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ownerStep() => Form(
    key: _ownerForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('owner-name'),
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Your name',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            return text.isEmpty || text.length > 120
                ? 'Enter your name.'
                : null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('gym-name'),
          controller: _gym,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Gym name',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            return text.length < 2 || text.length > 120
                ? 'Enter a gym name with 2–120 characters.'
                : null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('owner-email'),
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            helperText: 'For receipts and account recovery.',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            return text.isEmpty ||
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)
                ? null
                : 'Enter a valid email, or leave it empty.';
          },
        ),
        _errorText(),
        const SizedBox(height: AppSpacing.xl),
        _primary('Create my gym', _createGym, busyLabel: 'Creating…'),
      ],
    ),
  );

  final _nameForm = GlobalKey<FormState>();

  Future<void> _createAccount() async {
    if (!_nameForm.currentState!.validate()) return;
    await _run(() async {
      final response = await ref
          .read(phoneAuthRepositoryProvider)
          .registerAccount(signupToken: _signupToken!, displayName: _name.text);
      await ref.read(sessionControllerProvider.notifier).adoptSignIn(response);
    });
  }

  Widget _nameStep() => Form(
    key: _nameForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _role == SignInRole.member
              ? 'If your gym already added this number, you will see your plan '
                    'straight away. If not, you can ask your gym to let you join.'
              : 'If the gym already added you as a trainer with this number, you '
                    'are in straight away. If not, you can ask the gym to let you join.',
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('your-name'),
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Your full name',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            return text.isEmpty || text.length > 120
                ? 'Enter your name.'
                : null;
          },
          onFieldSubmitted: (_) => _createAccount(),
        ),
        _errorText(),
        const SizedBox(height: AppSpacing.xl),
        _primary('Continue', _createAccount, busyLabel: 'Setting up…'),
      ],
    ),
  );
}
