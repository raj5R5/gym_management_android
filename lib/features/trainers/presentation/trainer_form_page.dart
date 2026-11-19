import '../../../shared/widgets/field_icon.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../data/trainer_failure.dart';
import '../models/trainer_draft.dart';
import '../models/trainer_models.dart';
import '../providers/trainer_providers.dart';
import 'trainer_components.dart';
import '../../../shared/validators/profile_validators.dart';

class TrainerFormPage extends ConsumerWidget {
  const TrainerFormPage({super.key, required this.gymId, this.trainerId});
  final String? gymId, trainerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != gymId) return const TrainerContextChanged();
    final scope = scopeFor(gym, trainerId ?? '');
    if (trainerId == null) {
      return _TrainerForm(key: ValueKey(scope), scope: scope);
    }
    final state = ref.watch(trainerProfileProvider(scope));
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError) {
      return TrainerError(
        error: state.error,
        retry: () => ref.invalidate(trainerProfileProvider(scope)),
      );
    }
    final trainer = state.asData?.value;
    return trainer == null
        ? const TrainerContextChanged()
        : _TrainerForm(key: ValueKey(scope), scope: scope, trainer: trainer);
  }
}

class _TrainerForm extends ConsumerStatefulWidget {
  const _TrainerForm({super.key, required this.scope, this.trainer});
  final TrainerScope scope;
  final TrainerProfile? trainer;
  @override
  ConsumerState<_TrainerForm> createState() => _TrainerFormState();
}

class _TrainerFormState extends ConsumerState<_TrainerForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late bool _address;
  String? _gender;
  TrainerStatus _status = TrainerStatus.active;
  bool get _editing => widget.trainer != null;
  @override
  void initState() {
    super.initState();
    final trainer = widget.trainer;
    final values = <String, String?>{
      'trainerCode': trainer?.trainerCode,
      'firstName': trainer?.firstName,
      'lastName': trainer?.lastName,
      'phone': trainer?.phone,
      'dateOfBirth': trainer?.dateOfBirth?.toString(),
      'line1': trainer?.address?.line1,
      'line2': trainer?.address?.line2,
      'city': trainer?.address?.city,
      'state': trainer?.address?.region,
      'postalCode': trainer?.address?.postalCode,
      'countryCode': trainer?.address?.countryCode,
      'specializations': trainer?.specializations?.join('\n'),
    };
    _fields = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value ?? '')),
    );
    _gender = trainer?.gender;
    _status = trainer?.status ?? TrainerStatus.active;
    _address = trainer?.address != null;
  }

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
      enabled: !ref.watch(trainerMutationProvider(widget.scope)).isLoading,
      decoration: InputDecoration(labelText: label, prefixIcon: FieldIcon(key)),
      validator: validator,
      maxLength: maxLength,
      keyboardType: keyboard,
      maxLines: key == 'specializations' ? 4 : 1,
      textInputAction: key == 'specializations'
          ? TextInputAction.newline
          : TextInputAction.next,
    ),
  );
  String? Function(String?) _required(int max) =>
      (value) => (value ?? '').trim().isEmpty || value!.trim().length > max
      ? 'Enter 1–$max characters.'
      : null;
  Future<void> _save() async {
    if (ref.read(trainerMutationProvider(widget.scope)).isLoading ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final draft = TrainerDraft(
      trainerCode: _value('trainerCode'),
      firstName: _value('firstName'),
      lastName: _value('lastName'),
      phone: _value('phone'),
      dateOfBirth: _value('dateOfBirth').isEmpty
          ? null
          : CalendarDate.parse(_value('dateOfBirth')),
      gender: _gender,
      status: _status,
      address: !_address
          ? null
          : ProfileAddress.fromJson({
              'line1': _value('line1'),
              'city': _value('city'),
              'countryCode': _value('countryCode'),
              for (final key in ['line2', 'state', 'postalCode'])
                if (_value(key).isNotEmpty) key: _value(key),
            }),
      specializations: specializationsFromInput(_value('specializations')),
    );
    final saved = await ref
        .read(trainerMutationProvider(widget.scope).notifier)
        .save(draft);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_editing ? 'Trainer updated.' : 'Trainer created.'),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.trainers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainerMutationProvider(widget.scope));
    final busy = state.isLoading;
    return PopScope(
      canPop: !busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to Trainers',
                    onPressed: busy
                        ? null
                        : () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(AppRoutes.trainers);
                            }
                          },
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      _editing ? 'Edit trainer' : 'Add trainer',
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
                    'Trainer code: ${widget.trainer!.trainerCode} (cannot be changed)',
                  ),
                )
              else
                _field(
                  'trainerCode',
                  'Trainer code',
                  validator: validateProfileCode,
                  maxLength: 32,
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
              DropdownButtonFormField<TrainerStatus>(
                itemHeight: null,
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('status'),
                  labelText: 'Status',
                ),
                items: TrainerStatus.values
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
              ),
              const SizedBox(height: 12),
              if (!_editing)
                const Text(
                  'This creates a trainer profile only. Login access and member assignments are managed separately.',
                ),
              const SizedBox(height: 16),
              Text(
                'Optional profile information',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _field(
                'dateOfBirth',
                'Date of birth (YYYY-MM-DD)',
                validator: validateBirthDate,
                maxLength: 10,
                keyboard: TextInputType.datetime,
              ),
              DropdownButtonFormField<String?>(
                itemHeight: null,
                isExpanded: true,
                initialValue: _gender,
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('gender'),
                  labelText: 'Gender',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not provided'),
                  ),
                  ...trainerGenders.map(
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
              _field(
                'specializations',
                'Specializations (one per line)',
                validator: validateSpecializations,
                keyboard: TextInputType.multiline,
              ),
              const Text(
                'Up to 10 distinct entries. Leave blank to clear specializations when editing.',
              ),
              if (state.hasError)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      state.error is TrainerFailure
                          ? (state.error as TrainerFailure).message
                          : 'Trainer could not be saved. Please try again.',
                    ),
                  ),
                ),
              if (state.error is TrainerFailure &&
                  (state.error as TrainerFailure).possiblySent)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'The save may have reached the server. Check Trainers before retrying; do not change the code just to retry.',
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
                    : Text(_editing ? 'Save changes' : 'Create trainer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
