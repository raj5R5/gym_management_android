import '../../../shared/widgets/icon_label.dart';
import '../../../shared/widgets/field_icon.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../models/billing_models.dart';
import '../data/billing_failure.dart';
import '../providers/plan_providers.dart';
import 'billing_components.dart';
import 'plan_summary_card.dart';

String planPath(String gymId, {String? planId}) =>
    '${AppRoutes.plans}/${planId ?? 'new'}?gymId=${Uri.encodeQueryComponent(gymId)}';

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key, this.initialActiveOnly = false});
  final bool initialActiveOnly;
  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  int _page = 1;
  AdminGymContext? _gym;
  late bool _activeOnly = widget.initialActiveOnly;
  @override
  void didUpdateWidget(PlansPage old) {
    super.didUpdateWidget(old);
    if (old.initialActiveOnly != widget.initialActiveOnly) {
      _activeOnly = widget.initialActiveOnly;
      _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (_gym != gym) {
      _gym = gym;
      _page = 1;
    }
    final request = (gym: gym, page: _page);
    final provider = _activeOnly
        ? activeManagedPlansProvider(request)
        : managedPlansProvider(request);
    final plans = ref.watch(provider);
    Future<void> refresh() async {
      ref.invalidate(provider);
      await ref
          .read(provider.future)
          .then<void>((_) {}, onError: (Object _) {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Plans',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh plans',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: () => context.push(planPath(gym.gymId)),
                icon: const Icon(Icons.add),
                label: const Text('New plan'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Active only'),
              selected: _activeOnly,
              onSelected: (selected) => setState(() {
                _activeOnly = selected;
                _page = 1;
              }),
            ),
          ),
          if (plans.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (plans.hasError)
            BillingError(
              error: plans.error,
              retry: () => ref.invalidate(provider),
            )
          else if (plans.asData?.value
              case final BillingPage<MembershipPlan> data) ...[
            if (data.items.isEmpty)
              const IconLabel(
                'No membership plans. Create your first plan.',
                icon: Icons.layers_outlined,
              ),
            ...data.items.map(
              (plan) => PlanSummaryCard(
                plan: plan,
                baseline: comparisonBaseline(data.items),
                onEdit: () =>
                    context.push(planPath(gym.gymId, planId: plan.id)),
              ),
            ),
            PageControls(
              page: data.pagination.page,
              total: data.pagination.total,
              previous: data.pagination.hasPrevious
                  ? () => setState(() => _page--)
                  : null,
              next: data.pagination.hasNext
                  ? () => setState(() => _page++)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class PlanFormPage extends ConsumerWidget {
  const PlanFormPage({super.key, required this.gymId, this.planId});
  final String? gymId, planId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != gymId) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The gym context changed. Return to Membership Plans to continue.',
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.plans),
              child: const Text('Return to Membership Plans'),
            ),
          ],
        ),
      );
    }
    final scope = (gym: gym, planId: planId ?? '');
    if (planId == null) return _PlanEditor(key: ValueKey(scope), scope: scope);
    final plan = ref.watch(planDetailProvider(scope));
    if (plan.isLoading) return const Center(child: CircularProgressIndicator());
    if (plan.hasError) {
      return BillingError(
        error: plan.error,
        retry: () => ref.invalidate(planDetailProvider(scope)),
      );
    }
    final value = plan.asData?.value;
    return value == null
        ? const SizedBox.shrink()
        : _PlanEditor(key: ValueKey(scope), scope: scope, plan: value);
  }
}

class _PlanEditor extends ConsumerStatefulWidget {
  const _PlanEditor({super.key, required this.scope, this.plan});
  final PlanScope scope;
  final MembershipPlan? plan;
  @override
  ConsumerState<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends ConsumerState<_PlanEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _name, _description, _duration, _price;
  late String _status;
  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _name = TextEditingController(text: plan?.name ?? '');
    _description = TextEditingController(text: plan?.description ?? '');
    _duration = TextEditingController(
      text: plan?.durationDays.toString() ?? '',
    );
    _price = TextEditingController(
      text: plan == null
          ? ''
          : '${plan.pricePaise ~/ 100}.${(plan.pricePaise % 100).toString().padLeft(2, '0')}',
    );
    _status = plan?.status ?? 'active';
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in [_name, _description, _duration, _price]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(planMutationProvider(widget.scope));
    final busy = mutation.isLoading;
    final blocked =
        mutation.error is BillingFailure &&
        (mutation.error as BillingFailure).uncertain;
    return PopScope(
      canPop: !busy,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back from plan form',
                onPressed: busy
                    ? null
                    : () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.plans);
                        }
                      },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.plan == null
                      ? 'Create membership plan'
                      : 'Edit membership plan',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (mutation.hasError) BillingError(error: mutation.error),
          if (blocked) ...[
            const Text(
              'Verify whether this plan was already saved before trying again.',
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => ref
                        .read(planMutationProvider(widget.scope).notifier)
                        .recheck(),
              child: const Text('Recheck plans'),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.plans),
              child: const Text('View Membership Plans'),
            ),
          ],
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('planName'),
                  controller: _name,
                  enabled: !busy && !blocked,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('name'),
                    labelText: 'Name',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a plan name.'
                      : value.trim().length > 120
                      ? 'Use at most 120 characters.'
                      : null,
                ),
                TextFormField(
                  key: const ValueKey('planDescription'),
                  controller: _description,
                  enabled: !busy && !blocked,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('description'),
                    labelText: 'Description (optional)',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 2000
                      ? 'Use at most 2000 characters.'
                      : null,
                ),
                TextFormField(
                  key: const ValueKey('planDuration'),
                  controller: _duration,
                  enabled: !busy && !blocked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('duration'),
                    labelText: 'Duration in days',
                  ),
                  validator: (value) {
                    final days = int.tryParse(value?.trim() ?? '');
                    return days == null || days < 1 || days > 3650
                        ? 'Enter 1–3650 whole days.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('planPrice'),
                  controller: _price,
                  enabled: !busy && !blocked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('price'),
                    labelText: 'Price in INR',
                    prefixText: '₹ ',
                    helperText: 'Zero is allowed for a free plan.',
                  ),
                  validator: (value) {
                    try {
                      parsePaymentRupees(value ?? '', allowZero: true);
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  key: const ValueKey('planStatus'),
                  initialValue: _status,
                  decoration: const InputDecoration(
                    prefixIcon: FieldIcon('status'),
                    labelText: 'Status',
                  ),
                  items: ['active', 'inactive']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: busy || blocked
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
                const SizedBox(height: 16),
                if (busy) const Center(child: CircularProgressIndicator()),
                FilledButton(
                  style: AppButtonStyles.primary(context),
                  onPressed: busy || blocked
                      ? null
                      : () async {
                          if (!_form.currentState!.validate()) return;
                          final draft = PlanDraft(
                            name: _name.text,
                            description: _description.text,
                            durationDays: int.parse(_duration.text.trim()),
                            pricePaise: parsePaymentRupees(
                              _price.text,
                              allowZero: true,
                            ),
                            status: _status,
                          );
                          final saved = await ref
                              .read(planMutationProvider(widget.scope).notifier)
                              .save(draft);
                          if (!context.mounted ||
                              ref.read(adminGymProvider) != widget.scope.gym) {
                            return;
                          }
                          if (saved == null) {
                            _scroll.jumpTo(0);
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Membership plan saved: ${saved.name}',
                              ),
                            ),
                          );
                          if (context.canPop()) {
                            context.pop(true);
                          } else {
                            context.go(AppRoutes.plans);
                          }
                        },
                  child: const Text('Save plan'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
