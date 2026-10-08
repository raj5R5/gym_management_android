import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../../shared/formatting/inr.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import 'billing_components.dart';
import 'plans_page.dart' show planPath;

class PurchasePage extends ConsumerStatefulWidget {
  const PurchasePage({super.key, required this.memberId, required this.gymId});
  final String memberId;
  final String? gymId;
  @override
  ConsumerState<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends ConsumerState<PurchasePage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _reference = TextEditingController();
  int _page = 1;
  MembershipPlan? _plan;
  bool _recordPayment = false;
  PaymentMethod _method = PaymentMethod.cash;
  PurchaseDraft? _review;
  BillingResult? _result;
  String? _selectionError;
  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PurchasePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gymId != widget.gymId ||
        oldWidget.memberId != widget.memberId) {
      _page = 1;
      _plan = null;
      _recordPayment = false;
      _method = PaymentMethod.cash;
      _review = null;
      _result = null;
      _selectionError = null;
      _amount.clear();
      _reference.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final scope = scopeFor(gym, widget.memberId);
    final member = ref.watch(memberProfileProvider(scope));
    final request = (scope: scope, page: _page);
    final plans = ref.watch(activePlansProvider(request));
    final mutation = ref.watch(billingMutationProvider(scope));
    final blocked =
        mutation.error is BillingFailure &&
        (mutation.error as BillingFailure).uncertain;
    final busy = mutation.isLoading;
    final draft = _review;
    return PopScope(
      canPop: !busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to membership',
                onPressed: busy
                    ? null
                    : () => context.go(membershipPath(scope)),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Purchase membership',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (member.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (member.hasError)
            BillingError(
              error: member.error,
              retry: () => ref.invalidate(memberProfileProvider(scope)),
            )
          else if (member.asData?.value case final MemberProfile profile) ...[
            Text(
              '${profile.name} · ${profile.memberCode} · ${profile.status.name}',
            ),
            const Text(
              'Manual payment recording only. No online payment or banking credentials.',
            ),
            if (_result case final BillingResult result) ...[
              BillingResultCard(result: result),
              FilledButton(
                onPressed: () => context.go(membershipPath(scope)),
                child: const Text('View updated history'),
              ),
            ] else ...[
              if (mutation.hasError) BillingError(error: mutation.error),
              if (blocked) ...[
                OutlinedButton(
                  onPressed: () => context.go(membershipPath(scope)),
                  child: const Text('Check membership and payment history'),
                ),
                const Text(
                  'Use the history screen to recheck before reviewing another purchase.',
                ),
              ],
              if (draft != null) ...[
                ProfileSection(
                  title: 'Review purchase',
                  children: [
                    Text(_plan!.name),
                    Text(
                      '${_plan!.durationDays} days · ${formatInrPaise(_plan!.pricePaise)}',
                    ),
                    const Text(
                      'The server sets the start date to today (UTC), resolves the end date and checks current plan terms and eligibility.',
                    ),
                    if (draft.payment case final ManualPayment payment) ...[
                      Text(
                        'Successful payment: ${formatInrPaise(payment.amountPaise)} · ${payment.method.label}',
                      ),
                      if (payment.reference.isNotEmpty)
                        Text('Reference: ${payment.reference}'),
                      Text(
                        'Paid at review time: ${payment.paidAt.toUtc().toIso8601String()} (UTC)',
                      ),
                    ] else
                      const Text('No payment will be recorded.'),
                  ],
                ),
                if (busy) const Center(child: CircularProgressIndicator()),
                FilledButton(
                  onPressed: busy || blocked
                      ? null
                      : () async {
                          final result = await ref
                              .read(billingMutationProvider(scope).notifier)
                              .purchase(draft);
                          if (!mounted ||
                              !matchesScope(
                                ref.read(adminGymProvider),
                                scope,
                              )) {
                            return;
                          }
                          setState(() {
                            _result = result;
                            if (result == null) _review = null;
                          });
                        },
                  child: const Text('Confirm purchase'),
                ),
                TextButton(
                  onPressed: busy ? null : () => setState(() => _review = null),
                  child: const Text('Edit purchase'),
                ),
              ] else
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProfileSection(
                        title: 'Select an active plan',
                        children: [
                          if (plans.isLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (plans.hasError)
                            BillingError(
                              error: plans.error,
                              retry: () =>
                                  ref.invalidate(activePlansProvider(request)),
                            )
                          else if (plans.asData?.value
                              case final BillingPage<MembershipPlan> data) ...[
                            if (data.items.isEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'No active membership plans. Create a plan before purchasing a membership.',
                                  ),
                                  OutlinedButton(
                                    onPressed: busy || blocked
                                        ? null
                                        : () async {
                                            final created = await context
                                                .push<bool>(
                                                  planPath(gym.gymId),
                                                );
                                            if (!mounted ||
                                                !matchesScope(
                                                  ref.read(adminGymProvider),
                                                  scope,
                                                )) {
                                              return;
                                            }
                                            if (created == true) {
                                              setState(() {
                                                _page = 1;
                                                _plan = null;
                                                _selectionError = null;
                                              });
                                            }
                                          },
                                    child: const Text('Create membership plan'),
                                  ),
                                ],
                              ),
                            ...data.items.map(
                              (plan) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                selected: _plan?.id == plan.id,
                                leading: Icon(
                                  _plan?.id == plan.id
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                                title: Text(plan.name),
                                subtitle: Text(
                                  '${plan.durationDays} days · ${formatInrPaise(plan.pricePaise)}${plan.description == null ? '' : '\n${plan.description}'}',
                                ),
                                onTap: busy || blocked
                                    ? null
                                    : () => setState(() {
                                        _plan = plan;
                                        _selectionError = null;
                                      }),
                              ),
                            ),
                            PageControls(
                              page: data.pagination.page,
                              total: data.pagination.total,
                              previous: !busy && data.pagination.hasPrevious
                                  ? () => setState(() => _page--)
                                  : null,
                              next: !busy && data.pagination.hasNext
                                  ? () => setState(() => _page++)
                                  : null,
                            ),
                          ],
                          if (_plan != null) Text('Selected: ${_plan!.name}'),
                          if (_selectionError != null)
                            Text(
                              _selectionError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Record a successful payment'),
                        value: _recordPayment,
                        onChanged: busy || blocked
                            ? null
                            : (value) => setState(() => _recordPayment = value),
                      ),
                      if (_recordPayment) ...[
                        TextFormField(
                          key: const ValueKey('paymentAmount'),
                          controller: _amount,
                          enabled: !busy && !blocked,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount in INR',
                            prefixText: '₹ ',
                            helperText:
                                'Example: 1500.50. Maximum ₹1,00,00,000.00.',
                          ),
                          validator: (value) {
                            try {
                              parsePaymentRupees(value ?? '');
                              return null;
                            } on FormatException catch (error) {
                              return error.message;
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<PaymentMethod>(
                          key: const ValueKey('paymentMethod'),
                          initialValue: _method,
                          decoration: const InputDecoration(
                            labelText: 'Payment method',
                          ),
                          items: PaymentMethod.values
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method.label),
                                ),
                              )
                              .toList(),
                          onChanged: busy || blocked
                              ? null
                              : (method) => setState(() => _method = method!),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('paymentReference'),
                          controller: _reference,
                          enabled: !busy && !blocked,
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: _method.requiresReference
                                ? 'Payment reference (required)'
                                : 'Payment reference (optional)',
                            helperText:
                                'Transaction reference only. Never enter card or banking credentials.',
                          ),
                          validator: (value) =>
                              paymentReferenceError(_method, value ?? ''),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy || blocked
                            ? null
                            : () {
                                final valid = _form.currentState!.validate();
                                setState(
                                  () => _selectionError = _plan == null
                                      ? 'Select an active membership plan.'
                                      : null,
                                );
                                if (!valid || _plan == null) return;
                                setState(
                                  () => _review = PurchaseDraft(
                                    planId: _plan!.id,
                                    payment: _recordPayment
                                        ? ManualPayment(
                                            amountPaise: parsePaymentRupees(
                                              _amount.text,
                                            ),
                                            method: _method,
                                            paidAt: DateTime.now().toUtc(),
                                            reference: _reference.text,
                                          )
                                        : null,
                                  ),
                                );
                              },
                        child: const Text('Review purchase'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
