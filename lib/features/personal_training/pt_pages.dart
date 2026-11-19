import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import 'pt.dart';
import 'pt_widgets.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';

enum _PtView { packages, commission }

enum PtListFilter {
  active('Active'),
  due('Payment due'),
  completed('Completed'),
  all('All');

  const PtListFilter(this.label);
  final String label;
}

/// Filters the package list; [due] includes completed packages still owing.
List<PtPackage> filterPtPackages(List<PtPackage> rows, PtListFilter filter) =>
    switch (filter) {
      PtListFilter.active =>
        rows.where((pkg) => pkg.status == PtStatus.active).toList(),
      PtListFilter.due => rows.where((pkg) => pkg.hasDue).toList(),
      PtListFilter.completed =>
        rows.where((pkg) => pkg.status != PtStatus.active).toList(),
      PtListFilter.all => rows,
    };

class PtPage extends ConsumerStatefulWidget {
  const PtPage({super.key});
  @override
  ConsumerState<PtPage> createState() => _PtPageState();
}

class _PtPageState extends ConsumerState<PtPage> {
  _PtView _view = _PtView.packages;
  PtListFilter _filter = PtListFilter.active;
  CommissionPeriod _period = CommissionPeriod.thisMonth;

  Future<void> _sell() async {
    final sold = await showModalBottomSheet<PtPackage>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SellPtSheet(),
    );
    if (sold == null || !mounted) return;
    invalidatePt(ref.invalidate);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sold ${sold.name} to ${sold.member?.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            96,
          ),
          children: [
            Text('Personal training', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<_PtView>(
              segments: const [
                ButtonSegment(
                  value: _PtView.packages,
                  label: Text('Packages'),
                  icon: Icon(Icons.fitness_center_outlined),
                ),
                ButtonSegment(
                  value: _PtView.commission,
                  label: Text('Commission'),
                  icon: Icon(Icons.percent),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (value) =>
                  setState(() => _view = value.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_view == _PtView.packages)
              ..._packages(theme)
            else
              ..._commission(theme),
          ],
        ),
        if (_view == _PtView.packages)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: FloatingActionButton.extended(
              heroTag: 'sell-pt',
              onPressed: _sell,
              icon: const Icon(Icons.add),
              label: const Text('Sell PT'),
            ),
          ),
      ],
    );
  }

  List<Widget> _packages(ThemeData theme) {
    final state = ref.watch(
      ptPackagesProvider((memberId: null, trainerId: null, status: null)),
    );
    final all = state.asData?.value;
    final rows = all == null ? null : filterPtPackages(all, _filter);
    return [
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final filter in PtListFilter.values)
            ChoiceChip(
              label: Text(
                all == null
                    ? filter.label
                    : '${filter.label} ${filterPtPackages(all, filter).length}',
              ),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (state.hasError && rows == null)
        _Retry(
          message: state.error is PtFailure
              ? (state.error! as PtFailure).message
              : 'Packages could not be loaded.',
          retry: () => ref.invalidate(ptPackagesProvider),
        )
      else if (rows == null)
        const Center(child: CircularProgressIndicator())
      else if (rows.isEmpty)
        PlainBlock(
          child: Column(
            children: [
              const Icon(Icons.fitness_center_outlined, size: 32),
              const SizedBox(height: AppSpacing.sm),
              Text(
                all!.isEmpty
                    ? 'Sell personal training packages: sessions with a trainer, '
                          'paid in parts if needed. Trainers log each session.'
                    : 'Nothing here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
      else
        for (final pkg in rows) ...[
          PtPackageTile(pkg: pkg),
          const SizedBox(height: AppSpacing.sm),
        ],
    ];
  }

  Future<void> _editRate(CommissionRate rate) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    final percent = await showDialog<double>(
      context: context,
      builder: (_) => _RateDialog(rate: rate),
    );
    if (percent == null || !mounted) return;
    try {
      await ref
          .read(ptRepositoryProvider)
          .setRate(gym.gymId, rate.trainer.id, percent);
      ref.invalidate(commissionRatesProvider);
    } on PtFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  List<Widget> _commission(ThemeData theme) {
    final report = ref.watch(commissionReportProvider(_period));
    final rates = ref.watch(commissionRatesProvider);
    final data = report.asData?.value;
    return [
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final period in CommissionPeriod.values)
            ChoiceChip(
              label: Text(period.label),
              selected: _period == period,
              onSelected: (_) => setState(() => _period = period),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (report.hasError && data == null)
        _Retry(
          message: report.error is PtFailure
              ? (report.error! as PtFailure).message
              : 'The report could not be loaded.',
          retry: () => ref.invalidate(commissionReportProvider(_period)),
        )
      else if (data == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        GlassCard(
          child: Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'PT collected',
                  value: formatCompactInrPaise(data.collectedPaise),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Commission',
                  value: formatCompactInrPaise(data.commissionPaise),
                ),
              ),
              Expanded(
                child: _Figure(label: 'Sessions', value: '${data.sessions}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Commission is on PT money collected in the period, at the rate '
          'each package was sold at.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final row in data.rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row.trainer.name),
            subtitle: Text(
              '${formatInrPaise(row.collectedPaise)} collected · '
              '${row.sessions} session${row.sessions == 1 ? '' : 's'}',
            ),
            trailing: Text(
              formatInrPaise(row.commissionPaise),
              style: theme.textTheme.titleMedium,
            ),
          ),
        if (data.rows.isEmpty)
          Text('No trainers yet.', style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: AppSpacing.lg),
      Text('Commission rates', style: theme.textTheme.titleMedium),
      Text(
        'A new rate applies to packages sold after the change.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      if (rates.asData?.value case final list?)
        for (final rate in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: Text(rate.trainer.name),
            subtitle: Text(rate.trainer.code),
            trailing: TextButton(
              onPressed: () => _editRate(rate),
              child: Text(formatPercent(rate.percent)),
            ),
          )
      else if (rates.hasError)
        _Retry(
          message: 'Rates could not be loaded.',
          retry: () => ref.invalidate(commissionRatesProvider),
        )
      else
        const LinearProgressIndicator(minHeight: 2),
    ];
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleLarge),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => PlainBlock(
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.rate});
  final CommissionRate rate;
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  final _form = GlobalKey<FormState>();
  late final _percent = TextEditingController(
    text: formatPercent(widget.rate.percent).replaceAll('%', ''),
  );

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.rate.trainer.name} commission'),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const ValueKey('pt-rate'),
        controller: _percent,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(
          labelText: 'Percent of PT payments',
          suffixText: '%',
        ),
        validator: (value) {
          final number = double.tryParse((value ?? '').trim());
          if (number == null || number < 0 || number > 100) {
            return 'Enter 0 to 100';
          }
          return RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value!.trim())
              ? null
              : 'At most two decimals';
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() ?? false) {
            Navigator.pop(context, double.parse(_percent.text.trim()));
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class PtPackageDetailPage extends ConsumerStatefulWidget {
  const PtPackageDetailPage({super.key, required this.packageId});
  final String packageId;
  @override
  ConsumerState<PtPackageDetailPage> createState() =>
      _PtPackageDetailPageState();
}

class _PtPackageDetailPageState extends ConsumerState<PtPackageDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(String gymId) action) async {
    final gymId = ref.read(ptGymIdProvider);
    if (gymId == null || _busy) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await action(gymId);
      invalidatePt(container.invalidate);
    } on PtFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logSession(PtPackage pkg) async {
    final result = await showDialog<({DateTime day, String? note})>(
      context: context,
      builder: (_) => PtLogSessionDialog(pkg: pkg),
    );
    if (result == null) return;
    await _run(
      (gymId) => ref
          .read(ptRepositoryProvider)
          .logSession(gymId, pkg.id, date: result.day, note: result.note),
    );
  }

  Future<void> _cancel(PtPackage pkg) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel ${pkg.name}?',
      message:
          '${pkg.sessionsLeft} unused session${pkg.sessionsLeft == 1 ? '' : 's'} '
          'will be dropped. Payments stay on record.',
      keepLabel: 'Keep package',
      confirmLabel: 'Cancel package',
      destructive: true,
    );
    if (confirmed != true) return;
    await _run((gymId) => ref.read(ptRepositoryProvider).cancel(gymId, pkg.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(ptPackageProvider(widget.packageId));
    final pkg = state.asData?.value;
    if (pkg == null) {
      return Center(
        child: state.hasError
            ? Text(
                state.error is PtFailure
                    ? (state.error! as PtFailure).message
                    : 'Package could not be loaded.',
              )
            : const CircularProgressIndicator(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              // Also opened with Navigator from the trainer home.
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                pkg.member?.name ?? pkg.name,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(pkg.name, style: theme.textTheme.titleMedium),
              Text(
                'with ${pkg.trainer?.name ?? 'trainer'} · from ${ptDay(context, pkg.startDate)}'
                '${pkg.expiresOn == null ? '' : ' to ${ptDay(context, pkg.expiresOn!.subtract(const Duration(days: 1)))}'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('${pkg.sessionsLeft}', style: theme.textTheme.displaySmall),
              Text(ptStatusLine(pkg), style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: pkg.sessionsUsed / pkg.sessionsTotal,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _busy || !pkg.canLogSession
                    ? null
                    : () => _logSession(pkg),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Log a session'),
              ),
            ],
          ),
        ),
        if (pkg.pricePaise != null) ...[
          const SizedBox(height: AppSpacing.md),
          PlainBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Price',
                        value: formatInrPaise(pkg.pricePaise!),
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: 'Paid',
                        value: formatInrPaise(pkg.paidPaise!),
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: 'Due',
                        value: formatInrPaise(pkg.balancePaise!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Trainer commission ${formatPercent(pkg.commissionPercent ?? 0)} of payments',
                  style: theme.textTheme.bodySmall,
                ),
                if (pkg.hasDue) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final paid = await showDialog<bool>(
                              context: context,
                              builder: (_) => PtPaymentDialog(pkg: pkg),
                            );
                            if (paid == true) invalidatePt(ref.invalidate);
                          },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record payment'),
                  ),
                ],
                for (final payment in pkg.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(formatInrPaise(payment.amountPaise)),
                    subtitle: Text(
                      '${ptDay(context, payment.paidAt)} · ${payment.method.replaceAll('_', ' ')}'
                      '${payment.reference == null ? '' : ' · ${payment.reference}'}',
                    ),
                    trailing: Text(
                      '${formatInrPaise(payment.commissionPaise)} comm.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Sessions', style: theme.textTheme.titleMedium),
        if (pkg.sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text('No sessions yet.', style: theme.textTheme.bodySmall),
          ),
        for (final (index, session) in pkg.sessions.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              child: Text(
                '${pkg.sessionsUsed - index}',
                style: theme.textTheme.labelSmall,
              ),
            ),
            title: Text(ptDay(context, session.date)),
            subtitle: session.note == null ? null : Text(session.note!),
          ),
        if (pkg.status == PtStatus.active && pkg.pricePaise != null) ...[
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: _busy ? null : () => _cancel(pkg),
            icon: const Icon(Icons.close),
            label: const Text('Cancel package'),
          ),
        ],
      ],
    );
  }
}

/// Picks the session day (today by default) and an optional note.
class PtLogSessionDialog extends StatefulWidget {
  const PtLogSessionDialog({super.key, required this.pkg});
  final PtPackage pkg;
  @override
  State<PtLogSessionDialog> createState() => _PtLogSessionDialogState();
}

class _PtLogSessionDialogState extends State<PtLogSessionDialog> {
  final _note = TextEditingController();
  late DateTime _day = _today;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.pkg.startDate;
    final first = DateTime(start.year, start.month, start.day);
    return AlertDialog(
      title: const Text('Log a session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_day == _today ? 'Today' : ptDay(context, _day)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: first.isAfter(_today)
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _day,
                      firstDate: first,
                      lastDate: _today,
                    );
                    if (picked != null) setState(() => _day = picked);
                  },
          ),
          TextField(
            key: const ValueKey('pt-session-note'),
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Legs, deadlift 80 kg',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            day: _day,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          )),
          child: const Text('Log session'),
        ),
      ],
    );
  }
}
