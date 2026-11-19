import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../leads/lead_widgets.dart';
import '../members/models/member_overview.dart';
import '../memberships/models/billing_models.dart';
import 'pt.dart';
import '../../shared/widgets/page_section.dart';
import '../../shared/widgets/card_reveal.dart';

String ptDay(BuildContext context, DateTime day) =>
    MaterialLocalizations.of(context).formatShortMonthDay(day);

/// One-line state of a package: what the owner acts on first.
String ptStatusLine(PtPackage pkg) {
  if (pkg.status == PtStatus.cancelled) return 'Cancelled';
  if (pkg.status == PtStatus.completed) return 'All sessions used';
  if (pkg.expired) return 'Expired with ${pkg.sessionsLeft} left';
  return '${pkg.sessionsLeft} of ${pkg.sessionsTotal} sessions left';
}

class PtPackageTile extends StatelessWidget {
  const PtPackageTile({
    super.key,
    required this.pkg,
    this.showMember = true,
    this.onTap,
    this.onLog,
  });
  final PtPackage pkg;
  final bool showMember;

  /// Replaces opening the owner's package route (the trainer home pushes its own).
  final VoidCallback? onTap;

  /// Shows a quick Log button when set and a session can be logged.
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = showMember
        ? (pkg.member?.name ?? 'Member')
        : '${pkg.name} · ${pkg.trainer?.name ?? 'Trainer'}';
    final subtitle = showMember
        ? '${pkg.name} · ${pkg.trainer?.name ?? 'Trainer'}'
        : ptStatusLine(pkg);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap:
            onTap ?? () => pushFromCard(context, '${AppRoutes.pt}/${pkg.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onLog != null && pkg.canLogSession)
                    FilledButton.tonalIcon(
                      onPressed: onLog,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Log'),
                    )
                  else if (pkg.hasDue)
                    Text(
                      '${formatInrPaise(pkg.balancePaise!)} due',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppPalette.amber,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: pkg.sessionsUsed / pkg.sessionsTotal,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                showMember ? ptStatusLine(pkg) : '${pkg.sessionsUsed} used',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Payment method plus the reference UPI, card and bank transfers need.
class PtPaymentFields extends StatelessWidget {
  const PtPaymentFields({
    super.key,
    required this.method,
    required this.onMethod,
    required this.reference,
    this.enabled = true,
  });
  final PaymentMethod method;
  final ValueChanged<PaymentMethod> onMethod;
  final TextEditingController reference;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<PaymentMethod>(
        initialValue: method,
        decoration: const InputDecoration(labelText: 'Paid by'),
        items: [
          for (final value in PaymentMethod.values)
            DropdownMenuItem(value: value, child: Text(value.label)),
        ],
        onChanged: enabled ? (value) => onMethod(value ?? method) : null,
      ),
      if (method.requiresReference) ...[
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const ValueKey('pt-reference'),
          controller: reference,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Transaction reference'),
          validator: (value) => (value ?? '').trim().length < 3
              ? 'Enter the reference from the receipt'
              : null,
        ),
      ],
    ],
  );
}

String? _rupees(
  String? value, {
  bool allowZero = false,
  bool optional = false,
}) {
  final text = (value ?? '').trim();
  if (optional && text.isEmpty) return null;
  try {
    parsePaymentRupees(text, allowZero: allowZero);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

/// Sells a PT package. [member] preselects the member (from their profile).
class SellPtSheet extends ConsumerStatefulWidget {
  const SellPtSheet({super.key, this.member});
  final PtPerson? member;
  @override
  ConsumerState<SellPtSheet> createState() => _SellPtSheetState();
}

class _SellPtSheetState extends ConsumerState<SellPtSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Personal training');
  final _sessions = TextEditingController(text: '12');
  final _price = TextEditingController();
  final _validDays = TextEditingController(text: '60');
  final _paid = TextEditingController();
  final _reference = TextEditingController();
  PtPerson? _member;
  String? _trainerId;
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sessions,
      _price,
      _validDays,
      _paid,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickMember() async {
    final picked = await showDialog<MemberOverviewRow>(
      context: context,
      builder: (_) => const MemberPickerDialog(title: 'Member'),
    );
    if (picked != null) {
      setState(
        () => _member = PtPerson.fromJson({
          'id': picked.member.id,
          'name': picked.member.name,
          'memberCode': picked.member.memberCode,
        }),
      );
    }
  }

  Future<void> _save() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _saving || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (_member == null || _trainerId == null) {
      setState(() => _error = 'Choose a member and a trainer.');
      return;
    }
    final price = parsePaymentRupees(_price.text, allowZero: true);
    final paid = _paid.text.trim().isEmpty
        ? null
        : parsePaymentRupees(_paid.text);
    if (paid != null && paid > price) {
      setState(() => _error = 'Paid now cannot be more than the price.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pkg = await ref
          .read(ptRepositoryProvider)
          .create(
            gym.gymId,
            memberId: _member!.id,
            trainerId: _trainerId!,
            name: _name.text.trim(),
            sessions: int.parse(_sessions.text.trim()),
            pricePaise: price,
            validDays: _validDays.text.trim().isEmpty
                ? null
                : int.parse(_validDays.text.trim()),
            paidNowPaise: paid,
            method: _method.wireValue,
            reference: _method.requiresReference
                ? _reference.text.trim()
                : null,
          );
      if (mounted) Navigator.pop(context, pkg);
    } on PtFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _count(String? value, int max, {bool optional = false}) {
    final text = (value ?? '').trim();
    if (optional && text.isEmpty) return null;
    final number = int.tryParse(text);
    return number == null || number < 1 || number > max
        ? 'Enter 1 to $max'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rates = ref.watch(commissionRatesProvider);
    final trainers = rates.asData?.value ?? const <CommissionRate>[];
    final hasPayment = _paid.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sell PT package', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(_member?.name ?? 'Choose member'),
                subtitle: _member == null ? null : Text(_member!.code),
                trailing: widget.member == null
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: widget.member == null && !_saving ? _pickMember : null,
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('pt-trainer'),
                initialValue: _trainerId,
                decoration: InputDecoration(
                  labelText: 'Trainer',
                  helperText: rates.isLoading
                      ? 'Loading trainers…'
                      : trainers.isEmpty
                      ? 'Add a trainer first'
                      : null,
                ),
                items: [
                  for (final rate in trainers)
                    DropdownMenuItem(
                      value: rate.trainer.id,
                      child: Text(
                        '${rate.trainer.name} · ${formatPercent(rate.percent)} commission',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                isExpanded: true,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _trainerId = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Package name',
                  counterText: '',
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('pt-sessions'),
                      controller: _sessions,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Sessions'),
                      validator: (value) => _count(value, 200),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _validDays,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valid for (days)',
                        hintText: 'No limit',
                      ),
                      validator: (value) => _count(value, 730, optional: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('pt-price'),
                      controller: _price,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        prefixText: '₹',
                      ),
                      validator: (value) => _rupees(value, allowZero: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('pt-paid'),
                      controller: _paid,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Paid now',
                        prefixText: '₹',
                        hintText: '0',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) => _rupees(value, optional: true),
                    ),
                  ),
                ],
              ),
              if (hasPayment) ...[
                const SizedBox(height: AppSpacing.sm),
                PtPaymentFields(
                  method: _method,
                  onMethod: (value) => setState(() => _method = value),
                  reference: _reference,
                  enabled: !_saving,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Sell package'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatPercent(double value) =>
    '${value == value.roundToDouble() ? value.toInt() : value}%';

/// Records a payment towards a package; pops true on success.
class PtPaymentDialog extends ConsumerStatefulWidget {
  const PtPaymentDialog({super.key, required this.pkg});
  final PtPackage pkg;
  @override
  ConsumerState<PtPaymentDialog> createState() => _PtPaymentDialogState();
}

class _PtPaymentDialogState extends ConsumerState<PtPaymentDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: _plain(widget.pkg.balancePaise ?? 0),
  );
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  static String _plain(int paise) => paise % 100 == 0
      ? '${paise ~/ 100}'
      : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _saving || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(ptRepositoryProvider)
          .addPayment(
            gym.gymId,
            widget.pkg.id,
            amountPaise: parsePaymentRupees(_amount.text),
            method: _method.wireValue,
            reference: _method.requiresReference
                ? _reference.text.trim()
                : null,
          );
      if (mounted) Navigator.pop(context, true);
    } on PtFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record PT payment'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${formatInrPaise(widget.pkg.balancePaise ?? 0)} unpaid'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('pt-payment-amount'),
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
              ),
              validator: (value) {
                final error = _rupees(value);
                if (error != null) return error;
                return parsePaymentRupees(value!) >
                        (widget.pkg.balancePaise ?? 0)
                    ? 'More than the unpaid amount'
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            PtPaymentFields(
              method: _method,
              onMethod: (value) => setState(() => _method = value),
              reference: _reference,
              enabled: !_saving,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Record'),
      ),
    ],
  );
}

/// Personal training on a member's profile: their packages and a Sell button.
class MemberPtCard extends ConsumerWidget {
  const MemberPtCard({super.key, required this.member});
  final PtPerson member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final packages = ref.watch(
      ptPackagesProvider((memberId: member.id, trainerId: null, status: null)),
    );
    final rows = packages.asData?.value ?? const <PtPackage>[];
    final shown = rows
        .where((pkg) => pkg.status == PtStatus.active || pkg.hasDue)
        .take(3)
        .toList();
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Personal training',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final sold = await showModalBottomSheet<PtPackage>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => SellPtSheet(member: member),
                  );
                  if (sold != null) invalidatePt(ref.invalidate);
                },
                icon: const Icon(Icons.add),
                label: const Text('Sell PT'),
              ),
            ],
          ),
          if (packages.hasError)
            Text(
              packages.error is PtFailure
                  ? (packages.error! as PtFailure).message
                  : 'Packages could not be loaded.',
              style: theme.textTheme.bodySmall,
            )
          else if (packages.isLoading && rows.isEmpty)
            const LinearProgressIndicator(minHeight: 2)
          else if (shown.isEmpty)
            Text(
              rows.isEmpty
                  ? 'No PT packages yet.'
                  : 'No active packages. ${rows.length} past.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final pkg in shown) ...[
              const SizedBox(height: AppSpacing.sm),
              PtPackageTile(pkg: pkg, showMember: false),
            ],
        ],
      ),
    );
  }
}
