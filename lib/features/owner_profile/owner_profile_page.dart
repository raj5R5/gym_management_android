import '../../shared/widgets/field_icon.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/navigation/form_navigation_guard.dart';
import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/profile_section.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/models/owner_registration.dart';
import '../members/photos/member_photo_models.dart';
import '../members/photos/member_photo_providers.dart';
import '../members/photos/member_photo_widgets.dart';
import 'owner_profile.dart';
import 'owner_profile_widgets.dart';
import 'owner_signup_photo.dart';

class OwnerProfilePage extends ConsumerWidget {
  const OwnerProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(ownerProfileProvider);
    final profile = currentOwnerProfile(ref);
    final target = ownerPhotoTarget(ref);
    return profile == null || target == null
        ? Center(
            child: value.isLoading
                ? const CircularProgressIndicator(
                    semanticsLabel: 'Loading owner profile',
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value.error is OwnerProfileFailure
                              ? (value.error as OwnerProfileFailure).message
                              : 'Profile unavailable.',
                        ),
                        TextButton(
                          onPressed: () => ref.invalidate(ownerProfileProvider),
                          child: const Text('Retry profile'),
                        ),
                      ],
                    ),
                  ),
          )
        : _ProfileForm(
            key: ValueKey(target.key),
            profile: profile,
            target: target,
          );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.profile, required this.target});
  final OwnerProfile profile;
  final MemberPhotoTarget target;
  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  final _password = TextEditingController();
  late Map<String, String> _saved;
  final _cancel = CancelToken();
  bool _busy = false, _handoff = true;
  String? _error, _photoError;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _saved = {
      'displayName': p.name,
      'email': p.email,
      'phone': p.phone,
      'gymName': p.gymName,
      'gymContactPhone': p.gymPhone,
      'gymContactEmail': p.gymEmail,
    };
    _fields = _saved.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    Future.microtask(_recoverSignupPhoto);
  }

  Future<void> _recoverSignupPhoto() async {
    try {
      final store = ref.read(ownerSignupPhotoStoreProvider);
      await store.recover();
      if (!mounted) return;
      await store.handoff(
        ref.read(appConfigProvider),
        widget.profile,
        ref.read(memberPhotoServiceProvider),
        widget.target,
      );
      if (mounted) ref.invalidate(memberPhotoControllerProvider(widget.target));
    } catch (_) {
      if (mounted) {
        setState(
          () => _photoError =
              'The optional sign-up photo could not be recovered. Retry recovery or select a photo below.',
        );
      }
    } finally {
      if (mounted) setState(() => _handoff = false);
    }
  }

  bool get _dirty => _fields.entries.any(
    (entry) => entry.value.text.trim() != _saved[entry.key],
  );
  Map<String, String> get _input =>
      _fields.map((key, value) => MapEntry(key, value.text.trim()));
  @override
  void dispose() {
    _cancel.cancel();
    for (final field in _fields.values) {
      field.dispose();
    }
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final scope = ref.read(adminGymProvider);
    final repository = ref.read(ownerProfileRepositoryProvider);
    if (scope == null ||
        scope.userId != widget.profile.userId ||
        scope.gymId != widget.profile.gymId) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final input = _input;
    try {
      final saved = await repository.save(scope, {
        ...input,
        if (_password.text.isNotEmpty) 'currentPassword': _password.text,
      }, _cancel);
      if (!mounted || ref.read(adminGymProvider) != scope) return;
      _saved = input;
      _password.clear();
      // Update public profile only; never rotate or replace credentials here.
      ref.invalidate(ownerProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile saved for ${saved.gymName}.')),
      );
    } on OwnerProfileFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The profile could not be confirmed. Retry saving the same details.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label,
    String? Function(String?) validate, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: TextFormField(
      key: ValueKey('profile-$key'),
      controller: _fields[key],
      enabled: !_busy,
      validator: validate,
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
      textCapitalization: keyboard == null
          ? TextCapitalization.words
          : TextCapitalization.none,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label, prefixIcon: FieldIcon(key)),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final photo = ref.watch(memberPhotoControllerProvider(widget.target)).value;
    final photoBusy = photo?.busy == true || _handoff;
    return FormNavigationGuard(
      path: AppRoutes.ownerProfile,
      dirty: () => _dirty,
      busy: () => _busy || photoBusy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentWidth,
            ),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to account',
                        onPressed: _busy || photoBusy
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'OWNER PROFILE',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OwnerCompletion(profile: widget.profile),
                  const SizedBox(height: AppSpacing.lg),
                  if (_photoError != null) ...[
                    Text(_photoError!),
                    TextButton(
                      onPressed: _handoff
                          ? null
                          : () {
                              setState(() => _handoff = true);
                              _recoverSignupPhoto();
                            },
                      child: const Text('Retry sign-up photo recovery'),
                    ),
                  ],
                  if (_handoff)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Checking optional sign-up photo',
                    ),
                  MemberPhotoEditor(
                    target: widget.target,
                    ownerPhotoUrl: widget.profile.photoUrl,
                    ownerPhotoRevision: widget.profile.photoRevision,
                    enabled: !_busy && !_handoff,
                  ),
                  ProfileSection(
                    title: 'Your details',
                    icon: Icons.person_outline,
                    children: [
                      _field('displayName', 'Full name', ownerFullNameError),
                      _field(
                        'email',
                        'Sign-in email',
                        ownerEmailError,
                        keyboard: TextInputType.emailAddress,
                      ),
                      _field(
                        'phone',
                        'Your phone (optional)',
                        ownerGymPhoneError,
                        keyboard: TextInputType.phone,
                      ),
                      if (_fields['email']!.text.trim().toLowerCase() !=
                          _saved['email']!.toLowerCase())
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your current password to change the email.'
                              : null,
                          decoration: const InputDecoration(
                            prefixIcon: FieldIcon('currentPassword'),
                            labelText: 'Current password',
                            helperText:
                                'Required only when changing your sign-in email.',
                          ),
                        ),
                    ],
                  ),
                  ProfileSection(
                    title: 'Gym details',
                    icon: Icons.fitness_center_outlined,
                    children: [
                      _field('gymName', 'Gym name', ownerGymNameError),
                      _field(
                        'gymContactPhone',
                        'Gym contact phone (optional)',
                        ownerGymPhoneError,
                        keyboard: TextInputType.phone,
                      ),
                      _field(
                        'gymContactEmail',
                        'Gym contact email (optional)',
                        (value) => value == null || value.trim().isEmpty
                            ? null
                            : ownerEmailError(value),
                        keyboard: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || photoBusy || !_dirty ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Saving profile…' : 'Save profile'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
