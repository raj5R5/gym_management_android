import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/providers/session_controller.dart';
import 'branches.dart';
import '../../shared/widgets/page_section.dart';

/// All branches at a glance; switch into one, or add a new branch.
class BranchesPage extends ConsumerStatefulWidget {
  const BranchesPage({super.key});
  @override
  ConsumerState<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends ConsumerState<BranchesPage> {
  BranchPeriod _period = BranchPeriod.thisMonth;

  Future<void> _add() async {
    final gymId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddBranchSheet(),
    );
    if (gymId == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Reload the account so the new branch's access is known, then open it.
    await ref.read(sessionControllerProvider.notifier).refreshSession();
    ref.invalidate(branchSummaryProvider);
    if (ref.read(adminGymIdsProvider).contains(gymId)) {
      ref.read(adminGymProvider.notifier).selectGym(gymId);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Branch added. You are now in the new branch.'),
        ),
      );
      if (mounted) context.go(AppRoutes.dashboard);
    }
  }

  void _open(BranchRow row) {
    ref.read(adminGymProvider.notifier).selectGym(row.gymId);
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(branchSummaryProvider(_period));
    final data = state.asData?.value;
    final current = ref.watch(adminGymProvider)?.gymId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add branch'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          120,
        ),
        children: [
          Text('Branches', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each branch has its own members, plans and money. Tap one to switch to it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final period in BranchPeriod.values)
                ChoiceChip(
                  label: Text(period.label),
                  selected: period == _period,
                  labelStyle: TextStyle(
                    color: period == _period ? AppPalette.onAccent : null,
                  ),
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (state.hasError)
            Column(
              children: [
                Text(
                  state.error is BranchFailure
                      ? (state.error! as BranchFailure).message
                      : 'Branches could not be loaded.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(branchSummaryProvider),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (data != null) ...[
            if (data.branches.length > 1) ...[
              _BranchCard(row: data.totals, period: _period, highlight: true),
              const SizedBox(height: AppSpacing.md),
            ],
            for (final row in data.branches) ...[
              _BranchCard(
                row: row,
                period: _period,
                current: row.gymId == current,
                onTap: () => _open(row),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (data.branches.length == 1)
              PlainBlock(
                child: Text(
                  'Opening another location? Add it as a branch. You can copy this gym’s plans and settings.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.row,
    required this.period,
    this.highlight = false,
    this.current = false,
    this.onTap,
  });
  final BranchRow row;
  final BranchPeriod period;
  final bool highlight, current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget figure(String label, String value, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
    return GlassCard(
      padding: EdgeInsets.zero,
      borderColor: current ? AppPalette.pearl : AppColors.cardBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    highlight ? Icons.domain : Icons.storefront_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      row.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (current)
                    Text('Current', style: theme.textTheme.labelSmall),
                  if (onTap != null && !current)
                    const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  figure('Active members', '${row.activeMembers}'),
                  figure(
                    'Collected · ${period.label.toLowerCase()}',
                    formatCompactInrPaise(row.collectedPaise),
                  ),
                  figure(
                    'Dues',
                    formatCompactInrPaise(row.duesPaise),
                    color: row.duesPaise > 0 ? AppPalette.accentLight : null,
                  ),
                  figure('Check-ins today', '${row.checkInsToday}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddBranchSheet extends ConsumerStatefulWidget {
  const AddBranchSheet({super.key});
  @override
  ConsumerState<AddBranchSheet> createState() => _AddBranchSheetState();
}

class _AddBranchSheetState extends ConsumerState<AddBranchSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _copyPlans = true, _copySettings = true, _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final gymId = await ref
          .read(branchRepositoryProvider)
          .create(
            name: _name.text.trim(),
            fromGymId: ref.read(adminGymProvider)?.gymId,
            copyPlans: _copyPlans,
            copySettings: _copySettings,
          );
      if (mounted) Navigator.pop(context, gymId);
    } on BranchFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add branch', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A branch is a separate gym under your account, with its own members and money.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('branch-name'),
                controller: _name,
                enabled: !_saving,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Branch name',
                  hintText: 'Iron Gym – Andheri',
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Enter a branch name'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Copy membership plans'),
                subtitle: const Text('Active plans from the current branch'),
                value: _copyPlans,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _copyPlans = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Copy settings'),
                subtitle: const Text('Timezone, GST number and UPI ID'),
                value: _copySettings,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _copySettings = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Adding…' : 'Add branch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
