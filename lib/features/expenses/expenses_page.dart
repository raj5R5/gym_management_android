import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/models/dashboard_models.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../memberships/models/billing_models.dart';
import 'expenses.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Month view of spending, by category, with add and remove.
class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});
  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  /// Months back from the current month; 0 = this month (server default).
  int _monthsBack = 0;

  ExpensePeriod get _period {
    if (_monthsBack == 0) return (from: null, to: null, page: 1);
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - _monthsBack);
    final last = DateTime(first.year, first.month + 1, 0);
    return (from: _iso(first), to: _iso(last), page: 1);
  }

  String get _monthLabel {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - _monthsBack);
    return '${_months[month.month - 1]} ${month.year}';
  }

  void _changed() {
    ref.invalidate(expensesProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddExpenseSheet(),
    );
    if (added == true) _changed();
  }

  Future<void> _remove(Expense expense) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title:
          'Remove ${formatInrPaise(expense.amountPaise)} ${expense.category.label.toLowerCase()} expense?',
      message: 'It will no longer count towards profit.',
      keepLabel: 'Keep expense',
      confirmLabel: 'Remove expense',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(expenseRepositoryProvider).remove(gym.gymId, expense.id);
      _changed();
    } on ExpenseFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(expensesProvider(_period));
    final data = state.asData?.value;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          120,
        ),
        children: [
          Text('Expenses', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() => _monthsBack++),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _monthLabel,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: _monthsBack == 0
                    ? null
                    : () => setState(() => _monthsBack--),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (state.hasError)
            Column(
              children: [
                Text(
                  state.error is ExpenseFailure
                      ? (state.error! as ExpenseFailure).message
                      : 'Expenses could not be loaded.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(expensesProvider),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (data != null) ...[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Spent', style: theme.textTheme.bodySmall),
                  Text(
                    formatCompactInrPaise(data.totalPaise),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (data.byCategory.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    for (final row in data.byCategory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(row.category.icon, size: 16),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(child: Text(row.category.label)),
                                Text(formatCompactInrPaise(row.amountPaise)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: data.totalPaise == 0
                                    ? 0
                                    : row.amountPaise / data.totalPaise,
                                minHeight: 4,
                                backgroundColor: AppPalette.graphite,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (data.expenses.isEmpty)
              const PlainBlock(
                child: Text(
                  'No expenses recorded for this month. Add rent, salaries, electricity and other costs to see your real profit.',
                ),
              )
            else
              SeparatedRows(
                indent: 40,
                children: [
                  for (final expense in data.expenses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(expense.category.icon),
                      title: Text(
                        expense.note == null
                            ? expense.category.label
                            : '${expense.category.label} · ${expense.note}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(DateTime.parse(expense.spentOn)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatCompactInrPaise(expense.amountPaise)),
                          IconButton(
                            tooltip: 'Remove expense',
                            onPressed: () => _remove(expense),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key});
  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.rent;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _day = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
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
          .read(expenseRepositoryProvider)
          .create(
            gym.gymId,
            category: _category,
            amountPaise: parsePaymentRupees(_amount.text),
            spentOn: CalendarDate.fromPicker(_day).toString(),
            paymentMethod: _method.wireValue,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on ExpenseFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
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
              Text('Add expense', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final category in ExpenseCategory.values)
                    ChoiceChip(
                      avatar: Icon(category.icon, size: 16),
                      label: Text(category.label),
                      selected: category == _category,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('expense-amount'),
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: (value) {
                  try {
                    parsePaymentRupees(value ?? '');
                    return null;
                  } on FormatException {
                    return 'Enter an amount like 2500 or 2500.50';
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _day,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) setState(() => _day = picked);
                            },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(localizations.formatMediumDate(_day)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<PaymentMethod>(
                      initialValue: _method,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Paid by'),
                      items: [
                        for (final method in PaymentMethod.values)
                          DropdownMenuItem(
                            value: method,
                            child: Text(method.label),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _method = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _note,
                enabled: !_saving,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'November rent',
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
                child: Text(_saving ? 'Saving…' : 'Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
