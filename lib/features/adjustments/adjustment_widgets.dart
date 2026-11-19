import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/providers/member_overview_providers.dart';
import '../members/providers/member_providers.dart';
import '../memberships/models/billing_models.dart';
import 'adjustments.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String dayLabel(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

/// Freeze and discount controls for one membership.
class MembershipAdjustmentsCard extends ConsumerWidget {
  const MembershipAdjustmentsCard({
    super.key,
    required this.scope,
    required this.subscriptionId,
  });
  final MemberScope scope;
  final String subscriptionId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(membershipAdjustmentsProvider(subscriptionId));
    ref.invalidate(
      membershipDetailProvider((scope: scope, subscriptionId: subscriptionId)),
    );
    ref.invalidate(memberMembershipsProvider(scope));
    ref.invalidate(memberSummaryProvider(scope));
    ref.invalidate(memberOverviewProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _endEarly(
    BuildContext context,
    WidgetRef ref,
    MembershipFreeze freeze,
  ) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    final upcoming = freeze.status == 'upcoming';
    final confirmed = await showConfirmDialog(
      context,
      title: upcoming ? 'Cancel this freeze?' : 'End freeze today?',
      message: upcoming
          ? 'All ${freeze.days} days go back to the member.'
          : 'Unused days go back to the member.',
      keepLabel: 'Keep freeze',
      confirmLabel: upcoming ? 'Cancel freeze' : 'End freeze',
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(adjustmentRepositoryProvider)
          .endFreeze(gym.gymId, subscriptionId, freeze.id);
      _refresh(ref);
    } on AdjustmentFailure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(membershipAdjustmentsProvider(subscriptionId));
    final data = state.asData?.value;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: PlainBlock(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Freeze & discount', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.isLoading && data == null)
              const LinearProgressIndicator(minHeight: 2)
            else if (state.hasError)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.error is AdjustmentFailure
                          ? (state.error! as AdjustmentFailure).message
                          : 'Details could not be loaded.',
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      membershipAdjustmentsProvider(subscriptionId),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (data != null) ...[
              if (data.discountPaise > 0)
                Text(
                  'Plan price ${formatCompactInrPaise(data.listPricePaise)} · '
                  'Discount −${formatCompactInrPaise(data.discountPaise)} · '
                  'Now ${formatCompactInrPaise(data.pricePaise)}',
                  style: theme.textTheme.bodyMedium,
                ),
              Text(
                'Frozen ${data.frozenDays} of ${data.maxFreezeDays} days · '
                'Ends ${dayLabel(data.endDate.subtract(const Duration(days: 1)))}',
                style: muted,
              ),
              for (final freeze in data.freezes.where((f) => f.days > 0))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        Icons.ac_unit,
                        size: 16,
                        color: freeze.status == 'current'
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          '${dayLabel(freeze.startDate)} – '
                          '${dayLabel(freeze.endDate.subtract(const Duration(days: 1)))}'
                          ' · ${freeze.days} days · ${switch (freeze.status) {
                            'current' => 'now',
                            'upcoming' => 'upcoming',
                            'ended' => 'ended early',
                            _ => 'done',
                          }}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (freeze.canEndEarly)
                        TextButton(
                          onPressed: () => _endEarly(context, ref, freeze),
                          child: Text(
                            freeze.status == 'upcoming'
                                ? 'Cancel'
                                : 'End early',
                          ),
                        ),
                    ],
                  ),
                ),
              if (!data.freezeAllowed && data.freezeBlockedReason != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(data.freezeBlockedReason!, style: muted),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (data.freezeAllowed)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final saved = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => FreezeSheet(
                            adjustments: data,
                            subscriptionId: subscriptionId,
                          ),
                        );
                        if (saved == true) _refresh(ref);
                      },
                      icon: const Icon(Icons.ac_unit),
                      label: const Text('Freeze membership'),
                    ),
                  if (data.balancePaise > 0)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final saved = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => DiscountSheet(
                            adjustments: data,
                            subscriptionId: subscriptionId,
                          ),
                        );
                        if (saved == true) _refresh(ref);
                      },
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text('Give discount'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FreezeSheet extends ConsumerStatefulWidget {
  const FreezeSheet({
    super.key,
    required this.adjustments,
    required this.subscriptionId,
  });
  final MembershipAdjustments adjustments;
  final String subscriptionId;
  @override
  ConsumerState<FreezeSheet> createState() => _FreezeSheetState();
}

class _FreezeSheetState extends ConsumerState<FreezeSheet> {
  late DateTime _start = widget.adjustments.earliestStart;
  late int _days = widget.adjustments.freezeDaysLeft < 7
      ? widget.adjustments.freezeDaysLeft
      : 7;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adjustmentRepositoryProvider)
          .freeze(
            gym.gymId,
            widget.subscriptionId,
            start: _start,
            days: _days,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on AdjustmentFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.adjustments;
    final back = _start.add(Duration(days: _days));
    final newLastDay = data.endDate.add(Duration(days: _days - 1));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Freeze membership', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${data.freezeDaysLeft} of ${data.maxFreezeDays} freeze days left. '
              'The membership end date moves later by the frozen days.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _start,
                        firstDate: data.earliestStart,
                        lastDate: data.latestStart,
                        helpText: 'Freeze starts',
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
              icon: const Icon(Icons.event_outlined),
              label: Text('Starts ${dayLabel(_start)}'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '$_days ${_days == 1 ? 'day' : 'days'}',
              style: theme.textTheme.titleMedium,
            ),
            if (data.freezeDaysLeft > 1)
              Slider(
                key: const ValueKey('freeze-days'),
                value: _days.toDouble(),
                min: 1,
                max: data.freezeDaysLeft.toDouble(),
                divisions: data.freezeDaysLeft - 1,
                label: '$_days',
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _days = value.round()),
              ),
            Text(
              'Back on ${dayLabel(back)}. Membership now ends ${dayLabel(newLastDay)}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Travelling for work',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Freeze for $_days days'),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscountSheet extends ConsumerStatefulWidget {
  const DiscountSheet({
    super.key,
    required this.adjustments,
    required this.subscriptionId,
  });
  final MembershipAdjustments adjustments;
  final String subscriptionId;
  @override
  ConsumerState<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<DiscountSheet> {
  bool _percent = false;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// The rupee amount the server will apply, or null when the input is invalid.
  int? get _amountPaise {
    final text = _value.text.trim();
    if (_percent) {
      final percent = double.tryParse(text);
      if (percent == null || percent <= 0 || percent > 100) return null;
      if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) return null;
      return (widget.adjustments.listPricePaise * percent / 100).round();
    }
    try {
      return parsePaymentRupees(text);
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    final gym = ref.read(adminGymProvider);
    final amount = _amountPaise;
    if (gym == null || _saving || amount == null) return;
    if (amount > widget.adjustments.balancePaise) {
      setState(
        () => _error =
            'At most ${formatCompactInrPaise(widget.adjustments.balancePaise)} (the unpaid amount).',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adjustmentRepositoryProvider)
          .discount(
            gym.gymId,
            widget.subscriptionId,
            amountPaise: _percent ? null : amount,
            percent: _percent ? double.parse(_value.text.trim()) : null,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on AdjustmentFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.adjustments;
    final amount = _amountPaise;
    final tooMuch = amount != null && amount > data.balancePaise;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Give discount', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Plan price ${formatCompactInrPaise(data.listPricePaise)} · '
              'Unpaid ${formatCompactInrPaise(data.balancePaise)}. '
              'A discount lowers what is still due; it can’t refund money already paid.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Amount ₹')),
                ButtonSegment(value: true, label: Text('Percent %')),
              ],
              selected: {_percent},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _percent = value.single;
                      _value.clear();
                      _error = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('discount-value'),
              controller: _value,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _percent ? 'Percent of plan price' : 'Amount (₹)',
                suffixText: _percent ? '%' : null,
                prefixText: _percent ? null : '₹ ',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (amount != null)
              Text(
                tooMuch
                    ? 'That is more than the unpaid ${formatCompactInrPaise(data.balancePaise)}.'
                    : '${formatCompactInrPaise(amount)} off · Still due ${formatCompactInrPaise(data.balancePaise - amount)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tooMuch ? theme.colorScheme.error : null,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              enabled: !_saving,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Festival offer',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving || amount == null || tooMuch ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : amount == null
                    ? 'Enter a discount'
                    : 'Give ${formatCompactInrPaise(amount)} discount',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
