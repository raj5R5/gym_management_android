import '../../../shared/widgets/field_icon.dart';
import 'dart:typed_data';
import '../../account_privacy/privacy_support_page.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/app_config.dart';
import '../../owner_profile/owner_signup_photo.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/iron_hero.dart';
import '../../../shared/widgets/titanium_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/profile_section.dart';
import '../data/owner_registration_failure.dart';
import '../models/owner_registration.dart';
import '../providers/owner_registration_providers.dart';

class OwnerSignupPage extends ConsumerStatefulWidget {
  const OwnerSignupPage({super.key});
  @override
  ConsumerState<OwnerSignupPage> createState() => _OwnerSignupPageState();
}

class _OwnerSignupPageState extends ConsumerState<OwnerSignupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _gymName = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false, _hidePassword = true, _hideConfirmation = true;
  OwnerRegistrationFailure? _failure;
  Uint8List? _photo;
  String? _photoError;
  bool _photoBusy = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final store = ref.read(ownerSignupPhotoStoreProvider);
        await store.recover();
        final preview = await store.preview();
        if (mounted) setState(() => _photo = preview);
      } catch (_) {
        if (mounted) {
          setState(
            () => _photoError =
                'The optional photo could not be restored. Choose it again or continue without a photo.',
          );
        }
      }
    });
  }

  Future<void> _choosePhoto(ImageSource source) async {
    if (_busy || _photoBusy) return;
    setState(() {
      _photoBusy = true;
      _photoError = null;
    });
    try {
      final store = ref.read(ownerSignupPhotoStoreProvider);
      await store.select(ref.read(appConfigProvider), source);
      final preview = await store.preview();
      if (mounted) setState(() => _photo = preview);
    } catch (_) {
      if (mounted) {
        setState(
          () => _photoError =
              'The photo could not be selected. Check photo permissions or try another source. Sign-up can continue without a photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _password,
      _confirmPassword,
      _gymName,
      _phone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited(String _) {
    if (_failure != null) setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (_busy || _photoBusy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref
          .read(ownerRegistrationRepositoryProvider)
          .register(
            OwnerRegistrationRequest(
              ownerFullName: _name.text,
              email: _email.text,
              password: _password.text,
              gymName: _gymName.text,
              gymContactPhone: _phone.text,
            ),
          );
      var photoNeedsAttention = false;
      try {
        if (_photo != null) {
          await ref
              .read(ownerSignupPhotoStoreProvider)
              .confirmRegistration(_email.text);
        }
      } catch (_) {
        // Registration already succeeded; report the independent photo issue
        // without encouraging another account-creation request.
        photoNeedsAttention = true;
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.go(AppRoutes.login, extra: const OwnerRegistrationSuccess());
        if (photoNeedsAttention) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Account created. The optional photo could not be prepared. Add it from Edit owner profile after signing in.',
              ),
            ),
          );
        }
      }
    } on OwnerRegistrationFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } catch (_) {
      if (mounted) {
        setState(
          () => _failure = const OwnerRegistrationFailure(
            OwnerRegistrationFailureKind.unexpected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field({
    required String name,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboard,
    bool password = false,
    bool hidden = false,
    VoidCallback? toggle,
    String? helper,
    List<String>? autofill,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey(name),
        controller: controller,
        enabled: !_busy,
        validator: validator,
        keyboardType: keyboard,
        obscureText: password && hidden,
        autocorrect: !password && keyboard != TextInputType.emailAddress,
        enableSuggestions: !password,
        autofillHints: autofill,
        onChanged: _edited,
        textCapitalization: capitalization,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: FieldIcon(name),
          helperText: helper,
          helperMaxLines: 5,
          errorMaxLines: 5,
          errorText: _failure?.fieldError(name),
          suffixIcon: password
              ? IconButton(
                  tooltip: hidden ? 'Show $label' : 'Hide $label',
                  onPressed: _busy || _photoBusy ? null : toggle,
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_photoBusy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        leading: IconButton(
          tooltip: 'Back to Login',
          onPressed: _busy || _photoBusy
              ? null
              : () => context.go(AppRoutes.login),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: TitaniumEntrance(
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const IronHero(
                          title: 'START YOUR\nGYM.',
                          eyebrow: 'OWNER SIGN-UP',
                          description: 'Create your gym owner account',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'After creating your account and gym, sign in to get started.',
                        ),
                        const SizedBox(height: 20),
                        ProfileSection(
                          title: 'Owner photo (optional)',
                          icon: Icons.add_a_photo_outlined,
                          subtitle:
                              'Upload after signing in · You can add or change it later',
                          children: [
                            if (_photo != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    _photo!,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.person_outline,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                            if (_photoBusy)
                              const LinearProgressIndicator(
                                semanticsLabel: 'Choosing optional photo',
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: _busy || _photoBusy
                                      ? null
                                      : () => _choosePhoto(ImageSource.gallery),
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: const Text('Gallery'),
                                ),
                                TextButton.icon(
                                  onPressed: _busy || _photoBusy
                                      ? null
                                      : () => _choosePhoto(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: const Text('Camera'),
                                ),
                                if (_photo != null)
                                  TextButton(
                                    onPressed: _busy || _photoBusy
                                        ? null
                                        : () async {
                                            try {
                                              await ref
                                                  .read(
                                                    ownerSignupPhotoStoreProvider,
                                                  )
                                                  .clear();
                                              if (mounted) {
                                                setState(() => _photo = null);
                                              }
                                            } catch (_) {
                                              if (mounted) {
                                                setState(
                                                  () => _photoError =
                                                      'The saved selection could not be cleared. Retry.',
                                                );
                                              }
                                            }
                                          },
                                    child: const Text('Remove selection'),
                                  ),
                              ],
                            ),
                            if (_photoError != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(_photoError!),
                              ),
                          ],
                        ),
                        ProfileSection(
                          title: 'Owner details',
                          icon: Icons.person_outline,
                          children: [
                            _field(
                              name: 'ownerFullName',
                              label: 'Owner full name',
                              controller: _name,
                              validator: ownerFullNameError,
                              autofill: const [AutofillHints.name],
                              capitalization: TextCapitalization.words,
                            ),
                            _field(
                              name: 'email',
                              label: 'Email',
                              controller: _email,
                              validator: ownerEmailError,
                              keyboard: TextInputType.emailAddress,
                              autofill: const [AutofillHints.email],
                            ),
                            _field(
                              name: 'password',
                              label: 'Password',
                              controller: _password,
                              validator: ownerPasswordError,
                              password: true,
                              hidden: _hidePassword,
                              toggle: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              autofill: const [AutofillHints.newPassword],
                            ),
                            _field(
                              name: 'confirmPassword',
                              label: 'Confirm password',
                              controller: _confirmPassword,
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Confirm your password.'
                                  : value != _password.text
                                  ? 'Passwords must match.'
                                  : null,
                              password: true,
                              hidden: _hideConfirmation,
                              toggle: () => setState(
                                () => _hideConfirmation = !_hideConfirmation,
                              ),
                              autofill: const [AutofillHints.newPassword],
                            ),
                          ],
                        ),
                        ProfileSection(
                          title: 'Gym details',
                          icon: Icons.fitness_center_outlined,
                          children: [
                            _field(
                              name: 'gymName',
                              label: 'Gym name',
                              controller: _gymName,
                              validator: ownerGymNameError,
                              capitalization: TextCapitalization.words,
                            ),
                            _field(
                              name: 'gymContactPhone',
                              label: 'Gym contact phone (optional)',
                              controller: _phone,
                              validator: ownerGymPhoneError,
                              keyboard: TextInputType.phone,
                            ),
                          ],
                        ),
                        if (_failure != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _failure!.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        FormField<bool>(
                          initialValue: false,
                          validator: (value) => value == true
                              ? null
                              : 'Confirm that you are at least 18 to create an owner account.',
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                key: const ValueKey('adultAccountConfirmation'),
                                contentPadding: EdgeInsets.zero,
                                value: field.value ?? false,
                                onChanged: _busy || _photoBusy
                                    ? null
                                    : field.didChange,
                                title: const Text(
                                  'I am at least 18 and authorized to manage this gym.',
                                ),
                              ),
                              if (field.errorText != null)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    field.errorText!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _busy || _photoBusy ? null : _submit,
                          child: _busy
                              ? Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: 'Creating account',
                                      ),
                                    ),
                                    const Text('Creating account…'),
                                  ],
                                )
                              : const Text('Create account'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy || _photoBusy
                              ? null
                              : () => context.go(AppRoutes.login),
                          child: const Text('Already have an account? Sign in'),
                        ),
                        PrivacySupportLink(enabled: !_busy && !_photoBusy),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
