import '../../../shared/widgets/field_icon.dart';
import '../photos/member_photo_widgets.dart';
import '../photos/member_photo_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/navigation/form_navigation_guard.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/member_failure.dart';
import '../models/member_draft.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import '../../../shared/widgets/birth_date_field.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../../app/theme/design_tokens.dart';

class MemberFormPage extends ConsumerWidget {
  const MemberFormPage({super.key, required this.gymId, this.memberId});
  final String? gymId, memberId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != gymId) return const MemberContextChanged();
    final scope = scopeFor(gym, memberId ?? '');
    if (memberId == null) {
      return _MemberForm(key: ValueKey(scope), scope: scope);
    }
    final state = ref.watch(memberProfileProvider(scope));
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError) {
      return MemberError(
        error: state.error,
        retry: () => ref.invalidate(memberProfileProvider(scope)),
      );
    }
    final member = state.asData?.value;
    return member == null
        ? const MemberContextChanged()
        : _MemberForm(key: ValueKey(scope), scope: scope, member: member);
  }
}

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm({super.key, required this.scope, this.member});
  final MemberScope scope;
  final MemberProfile? member;
  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late bool _address, _emergency;
  String? _gender;
  MemberStatus _status = MemberStatus.active;
  late final List<Object?> _initialValues;
  bool _saved = false;
  List<Object?> get _values => [
    for (final field in _fields.values) field.text,
    _gender,
    _status,
    _address,
    _emergency,
  ];
  bool get _dirty => !_saved && !_sameValues();
  bool _sameValues() {
    final current = _values;
    return List.generate(
      current.length,
      (i) => current[i] == _initialValues[i],
    ).every((equal) => equal);
  }

  bool get _editing => widget.member != null;
  @override
  void initState() {
    super.initState();
    final member = widget.member;
    final values = <String, String?>{
      'memberCode': member?.memberCode,
      'firstName': member?.firstName,
      'lastName': member?.lastName,
      'phone': member?.phone,
      'dateOfBirth': member?.dateOfBirth?.toString(),
      'line1': member?.address?.line1,
      'line2': member?.address?.line2,
      'city': member?.address?.city,
      'state': member?.address?.region,
      'postalCode': member?.address?.postalCode,
      'countryCode': member?.address?.countryCode,
      'contactName': member?.emergencyContact?.name,
      'contactPhone': member?.emergencyContact?.phone,
      'relationship': member?.emergencyContact?.relationship,
    };
    _fields = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value ?? '')),
    );
    _gender = member?.gender;
    _status = member?.status ?? MemberStatus.active;
    _address = member?.address != null;
    _emergency = member?.emergencyContact != null;
    _initialValues = _values;
    for (final field in _fields.values) {
      field.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();
  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    int? maxLength,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: _fields[key],
      enabled: !ref.watch(memberMutationProvider(widget.scope)).isLoading,
      decoration: InputDecoration(labelText: label, prefixIcon: FieldIcon(key)),
      validator: validator,
      maxLength: maxLength,
      keyboardType: keyboard,
      textInputAction: TextInputAction.next,
    ),
  );
  String? Function(String?) _required(int max) =>
      (value) => (value ?? '').trim().isEmpty || value!.trim().length > max
      ? 'Enter 1–$max characters.'
      : null;
  Future<void> _save() async {
    if (ref.read(memberMutationProvider(widget.scope)).isLoading ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final draft = MemberDraft(
      firstName: _value('firstName'),
      lastName: _value('lastName'),
      phone: _value('phone'),
      dateOfBirth: _value('dateOfBirth').isEmpty
          ? null
          : CalendarDate.parse(_value('dateOfBirth')),
      gender: _gender,
      status: _editing ? _status : null,
      address: !_address
          ? null
          : MemberAddress.fromJson({
              'line1': _value('line1'),
              'city': _value('city'),
              'countryCode': _value('countryCode'),
              for (final key in ['line2', 'state', 'postalCode'])
                if (_value(key).isNotEmpty) key: _value(key),
            }),
      emergencyContact: !_emergency
          ? null
          : EmergencyContact.fromJson({
              'name': _value('contactName'),
              'phone': _value('contactPhone'),
              if (_value('relationship').isNotEmpty)
                'relationship': _value('relationship'),
            }),
    );
    final saved = await ref
        .read(memberMutationProvider(widget.scope).notifier)
        .save(draft);
    if (saved == null || !mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_editing ? 'Member updated.' : 'Member created.')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.members);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberMutationProvider(widget.scope));
    final photoTarget = memberPhotoTarget(ref, memberId: widget.member?.id);
    final photoBusy =
        photoTarget != null &&
        ref
                .watch(memberPhotoControllerProvider(photoTarget))
                .asData
                ?.value
                .busy ==
            true;
    final busy = state.isLoading || photoBusy;
    return FormNavigationGuard(
      path: _editing
          ? '${AppRoutes.members}/${widget.member!.id}/edit'
          : '${AppRoutes.members}/new',
      dirty: () => _dirty,
      busy: () =>
          ref.read(memberMutationProvider(widget.scope)).isLoading ||
          photoTarget != null &&
              ref
                      .read(memberPhotoControllerProvider(photoTarget))
                      .asData
                      ?.value
                      .busy ==
                  true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SoftPanel(
          tone: AppTone.neutral,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to Members',
                      onPressed: busy
                          ? null
                          : () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go(AppRoutes.members);
                              }
                            },
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        _editing ? 'Edit member' : 'Add member',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Member code: ${widget.member!.memberCode} (cannot be changed)',
                    ),
                  ),
                _field(
                  'firstName',
                  'First name',
                  validator: validateName,
                  maxLength: 80,
                ),
                _field(
                  'lastName',
                  'Last name',
                  validator: validateName,
                  maxLength: 80,
                ),
                _field(
                  'phone',
                  'Phone',
                  validator: validatePhone,
                  maxLength: 25,
                  keyboard: TextInputType.phone,
                ),
                if (_editing)
                  DropdownButtonFormField<MemberStatus>(
                    itemHeight: null,
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(
                      prefixIcon: FieldIcon('status'),
                      labelText: 'Status',
                    ),
                    items: MemberStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.name),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _status = value!),
                  )
                else
                  const Text(
                    'New members are active. Login access, memberships, payments and trainer assignments are not created by this form.',
                  ),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                Text(
                  'Optional profile information',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                BirthDateField(
                  controller: _fields['dateOfBirth']!,
                  enabled: !busy,
                  validator: validateMemberBirthDate,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Members must be 18 or older.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String?>(
                  itemHeight: null,
                  isExpanded: true,
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('gender'),
                    labelText: 'Gender (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Not provided'),
                    ),
                    ...memberGenders.map(
                      (gender) => DropdownMenuItem(
                        value: gender,
                        child: Text(
                          gender.replaceAll('_', ' '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _gender = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include address'),
                  subtitle: _editing
                      ? const Text('Uncheck to clear the saved address.')
                      : null,
                  value: _address,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _address = value!),
                ),
                if (_address) ...[
                  _field(
                    'line1',
                    'Address line 1',
                    validator: _required(200),
                    maxLength: 200,
                  ),
                  _field('line2', 'Address line 2', maxLength: 200),
                  _field(
                    'city',
                    'City',
                    validator: _required(100),
                    maxLength: 100,
                  ),
                  _field('state', 'State', maxLength: 100),
                  _field('postalCode', 'Postal code', maxLength: 20),
                  _field(
                    'countryCode',
                    'Country code (two uppercase letters)',
                    validator: (value) =>
                        RegExp(r'^[A-Z]{2}$').hasMatch((value ?? '').trim())
                        ? null
                        : 'Enter a two-letter uppercase country code.',
                    maxLength: 2,
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include emergency contact'),
                  subtitle: _editing
                      ? const Text(
                          'Uncheck to clear the saved emergency contact.',
                        )
                      : null,
                  value: _emergency,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _emergency = value!),
                ),
                if (_emergency) ...[
                  _field(
                    'contactName',
                    'Emergency contact name',
                    validator: _required(120),
                    maxLength: 120,
                  ),
                  _field(
                    'contactPhone',
                    'Emergency contact phone',
                    validator: validatePhone,
                    maxLength: 25,
                    keyboard: TextInputType.phone,
                  ),
                  _field('relationship', 'Relationship', maxLength: 80),
                ],
                if (photoTarget != null) ...[
                  const SizedBox(height: 16),
                  MemberPhotoEditor(
                    target: photoTarget,
                    member: widget.member,
                    enabled: !state.isLoading,
                  ),
                  const SizedBox(height: 16),
                ],
                if (state.hasError)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        state.error is MemberFailure
                            ? (state.error as MemberFailure).message
                            : 'Member could not be saved. Please try again.',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  style: AppButtonStyles.primary(context),
                  onPressed: busy ? null : _save,
                  child: busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('Saving…'),
                          ],
                        )
                      : Text(_editing ? 'Save changes' : 'Create member'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
