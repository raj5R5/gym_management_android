import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import 'gym_settings.dart';
import '../../shared/widgets/page_section.dart';

class GymSettingsPage extends ConsumerWidget {
  const GymSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gymSettingsProvider);
    final gym = ref.watch(adminGymProvider);
    final settings = state.asData?.value;
    if (gym == null) return const SizedBox.shrink();
    if (settings != null) {
      return _SettingsForm(key: ValueKey(gym), gym: gym, initial: settings);
    }
    return Center(
      child: state.hasError
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.error is GymSettingsFailure
                        ? (state.error! as GymSettingsFailure).message
                        : 'Gym settings could not be loaded.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(gymSettingsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : const CircularProgressIndicator(
              semanticsLabel: 'Loading gym settings',
            ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({super.key, required this.gym, required this.initial});
  final AdminGymContext gym;
  final GymSettings initial;
  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late String? _timezone = widget.initial.timezoneConfigured
      ? widget.initial.timezone
      : null;
  late final _gstin = TextEditingController(text: widget.initial.gstin ?? '');
  late final _line1 = TextEditingController(
    text: widget.initial.address?.line1 ?? '',
  );
  late final _line2 = TextEditingController(
    text: widget.initial.address?.line2 ?? '',
  );
  late final _city = TextEditingController(
    text: widget.initial.address?.city ?? '',
  );
  late final _state = TextEditingController(
    text: widget.initial.address?.state ?? '',
  );
  late final _postal = TextEditingController(
    text: widget.initial.address?.postalCode ?? '',
  );
  late final _upiId = TextEditingController(text: widget.initial.upiId ?? '');
  late final _upiName = TextEditingController(
    text: widget.initial.upiPayeeName ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _gstin,
      _line1,
      _line2,
      _city,
      _state,
      _postal,
      _upiId,
      _upiName,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  bool get _hasAddress => [
    _line1,
    _line2,
    _city,
    _state,
    _postal,
  ].any((c) => c.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final changes = <String, Object?>{
      if (_timezone != null) 'timezone': _timezone,
      'gstin': _optional(_gstin)?.toUpperCase(),
      'upiId': _optional(_upiId)?.toLowerCase(),
      'upiPayeeName': _optional(_upiName),
      'address': _hasAddress
          ? GymAddress(
              line1: _line1.text.trim(),
              line2: _optional(_line2),
              city: _city.text.trim(),
              state: _optional(_state),
              postalCode: _optional(_postal),
            ).toJson()
          : null,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(gymSettingsRepositoryProvider)
          .update(widget.gym.gymId, changes);
      if (!mounted) return;
      ref.invalidate(gymSettingsProvider);
      // Dates and "today" on the dashboard depend on the timezone.
      ref.invalidate(dashboardProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gym settings saved')));
      Navigator.of(context).maybePop();
    } on GymSettingsFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.initial.timezone;
    final zones = [
      ...commonGymTimezones,
      if (current != null &&
          !commonGymTimezones.any((zone) => zone.$1 == current))
        (current, current),
    ];
    return Form(
      key: _form,
      // Not a lazy ListView: off-screen fields must stay built so the Form
      // validates them (a disposed field is silently skipped).
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gym settings', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Used for membership dates, receipts and today’s figures.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PlainBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Timezone', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Membership start and end dates, expiry and “today” follow this timezone.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (!widget.initial.timezoneConfigured) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Not set yet. Until you choose one, the gym uses UTC, '
                      'which is 5½ hours behind India.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.amber,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('timezone'),
                    initialValue: _timezone,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Gym timezone',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                    items: [
                      for (final zone in zones)
                        DropdownMenuItem(
                          value: zone.$1,
                          child: Text(
                            zone.$1 == zone.$2
                                ? zone.$1
                                : '${zone.$2} · ${zone.$1}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (value) =>
                        value == null ? 'Choose your gym’s timezone' : null,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _timezone = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PlainBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tax', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Optional. Add it if your gym is GST registered, so it can appear on receipts.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('gstin'),
                    controller: _gstin,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'GST number (optional)',
                      hintText: '15-character GSTIN',
                      counterText: '',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim().toUpperCase();
                      if (text.isEmpty || gstinPattern.hasMatch(text)) {
                        return null;
                      }
                      return 'Enter a 15-character GST number';
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PlainBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Gym address', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Optional. Shown on receipts. Leave every field empty to remove it.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _field(_line1, 'Address line 1', 200, required: true),
                  _field(_line2, 'Address line 2 (optional)', 200),
                  _field(_city, 'City', 100, required: true),
                  _field(_state, 'State (optional)', 100),
                  _field(
                    _postal,
                    'PIN code (optional)',
                    12,
                    keyboard: TextInputType.number,
                    validator: (value) =>
                        value.isEmpty ||
                            RegExp(r'^[A-Za-z0-9 -]{3,12}$').hasMatch(value)
                        ? null
                        : 'Enter a valid PIN code',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PlainBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('UPI payments', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Optional. Lets members pay by scanning a QR with GPay, PhonePe or Paytm.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('upiId'),
                    controller: _upiId,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'UPI ID (optional)',
                      hintText: 'yourgym@okaxis',
                      prefixIcon: Icon(Icons.qr_code_2),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim().toLowerCase();
                      if (text.isEmpty || upiIdPattern.hasMatch(text)) {
                        return null;
                      }
                      return 'Enter a UPI ID like yourgym@okaxis';
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('upiPayeeName'),
                    controller: _upiName,
                    enabled: !_saving,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: 'Name shown in UPI apps (optional)',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int max, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    String? Function(String value)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      maxLength: max,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (value) {
        final text = (value ?? '').trim();
        // Address lines are only required once any address field is filled.
        if (required && text.isEmpty && _hasAddress) {
          return 'Required for the address';
        }
        return validator?.call(text);
      },
    ),
  );
}
