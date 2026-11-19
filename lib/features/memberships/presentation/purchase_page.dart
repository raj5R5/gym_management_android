import '../../../shared/widgets/icon_label.dart';
import '../../../shared/widgets/field_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart';
import '../../../shared/formatting/inr.dart';
import '../../../app/theme/design_tokens.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import '../providers/payment_providers.dart';
import '../../../shared/formatting/payment_date.dart';
import 'billing_components.dart';
import 'plans_page.dart' show planPath;
import '../models/membership_eligibility.dart';
import 'membership_eligibility_notice.dart';

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
  String? _paymentNotice;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_paymentChanged);
    _reference.addListener(_paymentChanged);
  }

  void _paymentChanged() {
    if (mounted) {
      setState(() {
        if (_paymentNotice != null && _amountError(_amount.text) == null) {
          _paymentNotice = null;
        }
      });
    }
  }

  void _clearPayment() {
    _amount.clear();
    _reference.clear();
    _method = PaymentMethod.cash;
  }

  int _initialAmount(String input) =>
      parseInitialPaymentRupees(input, planPricePaise: _plan!.pricePaise);

  void _selectPlan(MembershipPlan plan) {
    setState(() {
      _plan = plan;
      _review = null;
      _selectionError = null;
      _paymentNotice = null;
      if (plan.pricePaise == 0) {
        _recordPayment = false;
        _clearPayment();
      } else if (_recordPayment && _amount.text.isNotEmpty) {
        try {
          _initialAmount(_amount.text);
        } on FormatException {
          _clearPayment();
          _paymentNotice =
              'The previous payment amount is not valid for this plan. Enter a new amount before reviewing.';
        }
      }
    });
  }

  String? _amountError(String? value) {
    if (_plan == null) return 'Choose a plan before entering payment.';
    try {
      _initialAmount(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _referenceError(String? value) {
    if (_plan == null) return null;
    try {
      if (_initialAmount(_amount.text) == 0) return null;
    } on FormatException {
      return null; // The amount field explains why payment cannot proceed.
    }
    return paymentReferenceError(_method, value ?? '');
  }

  bool get _positivePayment {
    if (!_recordPayment || _plan == null) return false;
    try {
      return _initialAmount(_amount.text) > 0;
    } on FormatException {
      return false;
    }
  }

  Widget _balanceSummary(BuildContext context) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    final int received;
    try {
      received = _recordPayment ? _initialAmount(_amount.text) : 0;
    } on FormatException {
      return const Text(
        'Enter a valid initial payment to see the remaining balance.',
      );
    }
    return Semantics(
      liveRegion: true,
      child: Text(
        'Initial payment: ${formatInrPaise(received)} · Remaining balance: ${formatInrPaise(plan.pricePaise - received)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

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
      _paymentNotice = null;
      _amount.clear();
      _reference.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) return const MemberContextChanged();
    final timezone = ref.watch(paymentTimezoneProvider(gym)).asData?.value;
    final scope = scopeFor(gym, widget.memberId);
    final member = ref.watch(memberProfileProvider(scope));
    final request = (scope: scope, page: _page);
    final plans = ref.watch(activePlansProvider(request));
    final eligibility = ref.watch(memberMembershipsProvider(scope));
    final existing = blockingMembership(eligibility.asData?.value ?? []);
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
              BillingResultCard(result: result, timezone: timezone),
              FilledButton(
                onPressed: () => context.go(membershipPath(scope)),
                child: const Text('View updated history'),
              ),
            ] else if (eligibility.isLoading)
              const Text('Checking membership eligibility…')
            else if (eligibility.hasError)
              BillingError(
                error: eligibility.error,
                retry: () => ref.invalidate(memberMembershipsProvider(scope)),
              )
            else if (existing != null)
              MembershipEligibilityNotice(
                membership: existing,
                scope: scope,
                retry: () => ref.invalidate(memberMembershipsProvider(scope)),
              )
            else if (eligibility.asData?.value == null)
              const MemberContextChanged()
            else ...[
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
                  icon: Icons.fact_check_outlined,
                  tone: AppTone.plan,
                  children: [
                    Text(_plan!.name),
                    Text(
                      '${_plan!.durationDays} days · ${formatInrPaise(_plan!.pricePaise)}',
                    ),
                    const Text(
                      'The server sets the start date to today in the gym timezone, resolves the end date and checks current plan terms and eligibility.',
                    ),
                    if (draft.payment case final ManualPayment payment) ...[
                      Text(
                        'Payment to record: ${formatInrPaise(payment.amountPaise)} · ${payment.method.label}',
                      ),
                      if (payment.reference.isNotEmpty)
                        IconLabel(
                          'Reference: ${payment.reference}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      Text(
                        'Payment date: ${formatPaymentDateTime(MaterialLocalizations.of(context), payment.paidAt, timezone: timezone)}',
                      ),
                    ] else
                      const Text('No payment will be recorded.'),
                    Text(
                      'Remaining balance: ${formatInrPaise(_plan!.pricePaise - (draft.payment?.amountPaise ?? 0))}',
                    ),
                    const Text(
                      'Payment is recorded only after backend confirmation.',
                    ),
                  ],
                ),
                if (busy) const Center(child: CircularProgressIndicator()),
                FilledButton(
                  style: AppButtonStyles.primary(context),
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
                        icon: Icons.card_membership_outlined,
                        tone: AppTone.plan,
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
                                                _recordPayment = false;
                                                _paymentNotice = null;
                                                _clearPayment();
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
                                    : () => _selectPlan(plan),
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
                      if (_plan != null) ...[
                        IconLabel(
                          'Plan price: ${formatInrPaise(_plan!.pricePaise)}',
                          icon: Icons.sell_outlined,
                        ),
                        if (_plan!.pricePaise == 0)
                          const Text(
                            'Free plan · ₹0.00. No initial payment is required.',
                          ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Record an initial payment'),
                        subtitle: const Text(
                          'Leave off to pay later. Enter the full price or a partial amount.',
                        ),
                        value: _recordPayment,
                        onChanged:
                            busy ||
                                blocked ||
                                _plan == null ||
                                _plan!.pricePaise == 0
                            ? null
                            : (value) => setState(() {
                                _recordPayment = value;
                                _paymentNotice = null;
                                if (!value) _clearPayment();
                              }),
                      ),
                      if (_recordPayment) ...[
                        if (_paymentNotice != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(_paymentNotice!),
                          ),
                        TextFormField(
                          key: const ValueKey('paymentAmount'),
                          controller: _amount,
                          enabled: !busy && !blocked,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const FieldIcon('amount'),
                            labelText: 'Amount in INR',
                            prefixText: '₹ ',
                            helperText:
                                'Maximum ${formatInrPaise(_plan!.pricePaise)}. Enter 0 to pay later.',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: _amountError,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: busy || blocked
                                ? null
                                : () {
                                    final price = _plan!.pricePaise;
                                    _amount.text =
                                        '${price ~/ 100}.${(price % 100).toString().padLeft(2, '0')}';
                                    setState(() => _paymentNotice = null);
                                  },
                            child: const Text('Use full plan price'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<PaymentMethod>(
                          itemHeight: null,
                          key: const ValueKey('paymentMethod'),
                          initialValue: _method,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            prefixIcon: FieldIcon('method'),
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
                          enabled: !busy && !blocked && _positivePayment,
                          maxLength: 120,
                          decoration: InputDecoration(
                            prefixIcon: const FieldIcon('reference'),
                            labelText:
                                _positivePayment && _method.requiresReference
                                ? 'Payment reference (required)'
                                : 'Payment reference (optional)',
                            helperText: _positivePayment
                                ? 'Transaction reference only. Never enter card or banking credentials.'
                                : 'A zero payment needs no reference and records no payment.',
                          ),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: _referenceError,
                        ),
                      ],
                      _balanceSummary(context),
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
                                    payment:
                                        _recordPayment &&
                                            _initialAmount(_amount.text) > 0
                                        ? ManualPayment(
                                            amountPaise: _initialAmount(
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
