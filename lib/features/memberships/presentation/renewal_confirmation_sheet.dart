import '../../../shared/widgets/icon_label.dart';
import '../../../shared/widgets/field_icon.dart';
import '../../../shared/widgets/titanium_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/providers/member_providers.dart';
import '../models/billing_models.dart';
import '../models/renewal_payment_draft.dart';
import '../models/renewal_preview.dart';
import '../providers/membership_providers.dart';
import '../providers/renewal_providers.dart';
import 'billing_components.dart';
import '../models/membership_eligibility.dart';
import 'membership_eligibility_notice.dart';
import '../../../shared/widgets/page_section.dart';

Future<BillingResult?> showRenewalConfirmation(
  BuildContext context,
  MemberScope scope,
  String subscriptionId,
) => showModalBottomSheet<BillingResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  showDragHandle: false,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => RenewalConfirmationSheet(
    request: (scope: scope, subscriptionId: subscriptionId),
  ),
);

class RenewalConfirmationSheet extends ConsumerStatefulWidget {
  const RenewalConfirmationSheet({super.key, required this.request});
  final RenewalRequest request;
  @override
  ConsumerState<RenewalConfirmationSheet> createState() =>
      _RenewalConfirmationSheetState();
}

class _RenewalConfirmationSheetState
    extends ConsumerState<RenewalConfirmationSheet> {
  late final AuthRepository _auth;
  late final int _revision;
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _reference = TextEditingController();
  MembershipPlan? _selected;
  bool _userSelected = false, _sending = false;
  int _step = 0, _page = 1;
  RenewalPaymentChoice _choice = RenewalPaymentChoice.full;
  PaymentMethod _method = PaymentMethod.cash;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _auth = ref.read(authRepositoryProvider);
    _revision = _auth.revision;
    _amount.addListener(_changed);
    _reference.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  bool _current() =>
      mounted &&
      matchesScope(ref.read(adminGymProvider), widget.request.scope) &&
      identical(ref.read(authRepositoryProvider), _auth) &&
      _auth.revision == _revision;
  RenewalPaymentDraft get _payment => RenewalPaymentDraft(
    choice: _choice,
    amount: _amount.text,
    method: _method,
    reference: _reference.text,
  );
  SelectedRenewalRequest get _previewRequest =>
      (membership: widget.request, planId: _selected!.id);
  void _select(MembershipPlan plan) {
    setState(() {
      _userSelected = true;
      _selected = plan;
      _notice = null;
      if (plan.pricePaise == 0) {
        _choice = RenewalPaymentChoice.later;
        _amount.clear();
        _reference.clear();
        _method = PaymentMethod.cash;
      }
    });
  }

  Future<void> _confirm(RenewalPreview preview) async {
    final controller = ref.read(
      renewalControllerProvider(widget.request).notifier,
    );
    if (_sending ||
        !_current() ||
        !controller.ready ||
        !controller.canStart ||
        _payment.validation(preview.pricePaise) != null) {
      return;
    }
    final current = ref.read(selectedRenewalPreviewProvider(_previewRequest));
    if (current.isLoading ||
        current.hasError ||
        !identical(current.asData?.value, preview)) {
      return;
    }
    setState(() {
      _sending = true;
      _notice = null;
    });
    final result = await controller.submit(
      preview,
      _payment.payment(preview.pricePaise, DateTime.now().toUtc()),
    );
    if (!mounted) return;
    if (_current() && result == null && controller.saved?.rejected == true) {
      _notice =
          'The server rejected this attempt without creating a renewal. Review the current plan, dates and payment before confirming a corrected request.';
      ref.invalidate(selectedRenewalPreviewProvider(_previewRequest));
    }
    setState(() => _sending = false);
  }

  Future<void> _retry() async {
    if (_sending || !_current()) return;
    setState(() => _sending = true);
    await ref
        .read(renewalControllerProvider(widget.request).notifier)
        .retrySaved();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(adminGymProvider);
    final recovery = ref.watch(renewalControllerProvider(widget.request));
    final controller = ref.read(
      renewalControllerProvider(widget.request).notifier,
    );
    final current = _current();
    final busy = _sending || controller.busy || recovery.isLoading;
    final saved = controller.saved;
    final confirmed = controller.confirmed;
    final detail = ref.watch(membershipDetailProvider(widget.request));
    final previous = ref.watch(renewalPreviousPlanProvider(widget.request));
    final plansRequest = (scope: widget.request.scope, page: _page);
    final plans = ref.watch(activePlansProvider(plansRequest));
    if (!_userSelected && _selected == null && previous.asData?.value != null) {
      _selected = previous.asData!.value;
    }
    final preview = _selected == null
        ? null
        : ref.watch(selectedRenewalPreviewProvider(_previewRequest));
    final quote = preview != null && !preview.isLoading && !preview.hasError
        ? preview.asData?.value
        : null;
    final canDraft =
        controller.ready && controller.canStart && confirmed == null;
    final eligibility = ref.watch(
      memberMembershipsProvider(widget.request.scope),
    );
    final existing = blockingMembership(eligibility.asData?.value ?? []);
    final dates = MaterialLocalizations.of(context);
    final children = <Widget>[
      Text(
        'Renew membership',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.lg),
      if (!current)
        const Text(
          'The account or gym changed. Close this preview and reopen the correct membership.',
        )
      else if (confirmed != null) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            'Renewal confirmed',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        BillingResultCard(result: confirmed),
        Text('Collected now: ${formatInrPaise(confirmed.receivedPaise)}'),
        Text(
          'New membership balance: ${formatInrPaise(confirmed.balancePaise)}',
        ),
        const Text('Previous membership dues remain separate.'),
        if (recovery.hasError) BillingError(error: recovery.error),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => _sending = true);
                  await controller.acknowledge();
                  if (!context.mounted) return;
                  if (_current() &&
                      controller.saved == null &&
                      !ref
                          .read(renewalControllerProvider(widget.request))
                          .hasError) {
                    Navigator.of(context).pop(confirmed);
                    return;
                  }
                  setState(() => _sending = false);
                },
          child: const Text('Done'),
        ),
      ] else if (!controller.ready) ...[
        if (recovery.isLoading) const LinearProgressIndicator(),
        const Text('Checking saved renewal before starting…'),
        if (recovery.hasError)
          BillingError(
            error: recovery.error,
            retry: busy ? null : controller.recheck,
          ),
      ] else if (!canDraft) ...[
        Text(
          busy
              ? 'Confirming renewal…'
              : saved?.conflict == true
              ? 'Saved renewal needs verification'
              : 'Recover saved renewal',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'The original plan, amount, payment timestamp and request key are preserved. Do not collect money again or start another renewal.',
        ),
        if (saved != null) ...[
          IconLabel(
            'Plan price: ${formatInrPaise(saved.request.pricePaise)}',
            icon: Icons.sell_outlined,
          ),
          Text(
            'Payment to verify: ${formatInrPaise(saved.request.receivedPaise)}',
          ),
        ],
        if (recovery.hasError) BillingError(error: recovery.error),
        if (controller.canRetry)
          FilledButton(
            onPressed: busy ? null : _retry,
            child: const Text('Retry saved renewal exactly'),
          )
        else
          const Text(
            'Check membership and payment history with an administrator. This operation remains blocked until safely verified.',
          ),
        TextButton(
          onPressed: busy ? null : controller.recheck,
          child: const Text('Recheck saved renewal'),
        ),
      ] else if (eligibility.isLoading)
        const Text('Checking membership eligibility…')
      else if (eligibility.hasError)
        BillingError(
          error: eligibility.error,
          retry: () =>
              ref.invalidate(memberMembershipsProvider(widget.request.scope)),
        )
      else if (existing != null)
        MembershipEligibilityNotice(
          membership: existing,
          scope: widget.request.scope,
          onView: () {
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.push(
              membershipPath(widget.request.scope, subscriptionId: existing.id),
            );
          },
          retry: () =>
              ref.invalidate(memberMembershipsProvider(widget.request.scope)),
        )
      else if (eligibility.asData?.value == null)
        const Text('Reopen this membership in the current gym.')
      else ...[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final entry in [
              (0, 'Choose plan'),
              (1, 'Payment'),
              (2, 'Review & confirm'),
            ])
              Chip(
                avatar: CircleAvatar(child: Text('${entry.$1 + 1}')),
                label: Text(entry.$2),
                backgroundColor: _step == entry.$1
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
        if (saved?.rejected == true)
          const Text(
            'This saved attempt was definitively rejected. Its original request is kept until a reviewed correction is durably saved.',
          ),
        if (recovery.hasError) BillingError(error: recovery.error),
        if (_step == 0) ...[
          if (previous.isLoading) const LinearProgressIndicator(),
          if (previous.hasError)
            BillingError(
              error: previous.error,
              retry: () =>
                  ref.invalidate(renewalPreviousPlanProvider(widget.request)),
            ),
          if (_selected != null)
            Text(
              'Selected plan: ${_selected!.name} · ${formatInrPaise(_selected!.pricePaise)}',
            ),
          if (plans.isLoading)
            const Text('Loading membership plans…')
          else if (plans.hasError)
            BillingError(
              error: plans.error,
              retry: () => ref.invalidate(activePlansProvider(plansRequest)),
            )
          else if (plans.asData?.value?.items.isEmpty ?? true)
            const Text(
              'No active membership plans. Configure an active plan in Membership Plans before renewing.',
            )
          else
            SeparatedRows(
              indent: 40,
              children: [
                for (final plan in plans.asData!.value!.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: _selected?.id == plan.id,
                    leading: Icon(
                      _selected?.id == plan.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: busy ? null : () => _select(plan),
                    title: Text(plan.name),
                    subtitle: Text(
                      '${plan.durationDays} days · ${formatInrPaise(plan.pricePaise)}',
                    ),
                  ),
              ],
            ),
          if (plans.asData?.value case final data?)
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
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed:
                busy ||
                    _selected == null ||
                    plans.isLoading ||
                    plans.hasError ||
                    plans.asData?.value?.pagination.total == 0 ||
                    previous.isLoading
                ? null
                : () => setState(() => _step = 1),
            child: const Text('Continue to Payment'),
          ),
        ] else if (_step == 1) ...[
          Text(_selected!.name, style: Theme.of(context).textTheme.titleLarge),
          IconLabel(
            'Plan price: ${formatInrPaise(_selected!.pricePaise)}',
            icon: Icons.sell_outlined,
          ),
          if (_selected!.pricePaise == 0)
            const Text('Free plan · ₹0.00. No payment is required.')
          else ...[
            DropdownButtonFormField<RenewalPaymentChoice>(
              itemHeight: null,
              isExpanded: true,
              initialValue: _choice,
              key: ValueKey(_choice),
              decoration: const InputDecoration(
                prefixIcon: FieldIcon('method'),
                labelText: 'Payment choice',
              ),
              items: const [
                DropdownMenuItem(
                  value: RenewalPaymentChoice.full,
                  child: Text('Full payment'),
                ),
                DropdownMenuItem(
                  value: RenewalPaymentChoice.partial,
                  child: Text('Partial payment'),
                ),
                DropdownMenuItem(
                  value: RenewalPaymentChoice.later,
                  child: Text('Pay later'),
                ),
              ],
              onChanged: (value) => setState(() {
                _choice = value!;
                if (value == RenewalPaymentChoice.later) {
                  _amount.clear();
                  _reference.clear();
                  _method = PaymentMethod.cash;
                }
              }),
            ),
            if (_choice == RenewalPaymentChoice.partial)
              TextFormField(
                key: const ValueKey('renewalAmount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('amount'),
                  labelText: 'Amount collected (INR)',
                ),
                validator: (_) {
                  try {
                    _payment.amountPaise(_selected!.pricePaise);
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
            if (_choice != RenewalPaymentChoice.later) ...[
              DropdownButtonFormField<PaymentMethod>(
                itemHeight: null,
                isExpanded: true,
                initialValue: _method,
                decoration: const InputDecoration(
                  prefixIcon: FieldIcon('method'),
                  labelText: 'Payment method',
                ),
                items: [
                  for (final method in PaymentMethod.values)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: (method) => setState(() => _method = method!),
              ),
              TextFormField(
                key: const ValueKey('renewalReference'),
                controller: _reference,
                decoration: InputDecoration(
                  prefixIcon: const FieldIcon('reference'),
                  labelText: _method.requiresReference
                      ? 'Reference (required)'
                      : 'Reference (optional)',
                ),
                validator: (value) =>
                    paymentReferenceError(_method, value ?? ''),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (_) {
              try {
                final received = _payment.amountPaise(_selected!.pricePaise);
                return Text(
                  'To record: ${formatInrPaise(received)} · Remaining: ${formatInrPaise(_selected!.pricePaise - received)}',
                );
              } on FormatException catch (error) {
                return Text(error.message);
              }
            },
          ),
          const Text(
            'Payment is recorded only after the backend confirms renewal.',
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    if (_form.currentState!.validate()) {
                      ref.invalidate(
                        selectedRenewalPreviewProvider(_previewRequest),
                      );
                      setState(() => _step = 2);
                    }
                  },
            child: const Text('Review & Confirm'),
          ),
        ] else ...[
          if (preview?.isLoading ?? true) ...[
            const LinearProgressIndicator(),
            const Text('Loading current renewal price and dates…'),
          ] else if (preview!.hasError)
            BillingError(
              error: preview.error,
              retry: () => ref.invalidate(
                selectedRenewalPreviewProvider(_previewRequest),
              ),
            )
          else if (quote != null) ...[
            SoftPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.memberName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconLabel(
                    'Member code: ${quote.memberCode}',
                    icon: Icons.badge_outlined,
                  ),
                  Text(quote.planName),
                  Text('Current plan duration: ${quote.durationDays} days'),
                  Text('Renewal price: ${formatInrPaise(quote.pricePaise)}'),
                  Text(
                    'Existing end date: ${dates.formatMediumDate(quote.previousEndDate.value)}',
                  ),
                  Text(
                    'Renewal starts: ${dates.formatMediumDate(quote.startDate.value)}',
                  ),
                  Text(
                    'Renewal ends: ${dates.formatMediumDate(quote.endDate.value)}',
                  ),
                  const Text(
                    'End dates are exclusive. Membership calendar dates follow the gym timezone.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (detail.isLoading)
              const Text('Checking previous membership balance…')
            else if (detail.hasError)
              BillingError(
                error: detail.error,
                retry: () =>
                    ref.invalidate(membershipDetailProvider(widget.request)),
              )
            else if (detail.asData?.value case final old?)
              Text(
                'Previous membership balance (separate): ${formatInrPaise(old.payments.balancePaise)}',
              ),
            Builder(
              builder: (_) {
                try {
                  final received = _payment.amountPaise(quote.pricePaise);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To record now: ${formatInrPaise(received)}'),
                      Text(
                        'New membership balance: ${formatInrPaise(quote.pricePaise - received)}',
                      ),
                      if (received > 0)
                        Text(
                          '${_method.label}${_reference.text.trim().isEmpty ? '' : ' · ${_reference.text.trim()}'}',
                        )
                      else
                        Text(
                          quote.pricePaise == 0
                              ? 'Free plan. No payment is due.'
                              : 'Pay later. No payment will be recorded.',
                        ),
                    ],
                  );
                } on FormatException catch (error) {
                  return Text(error.message);
                }
              },
            ),
            if (_payment.validation(quote.pricePaise) != null)
              Text(_payment.validation(quote.pricePaise)!),
            const Text(
              'Previous dues are not transferred or marked paid. Renewal and any initial payment are saved together. Payment is recorded only after backend confirmation.',
            ),
            FilledButton(
              style: AppButtonStyles.primary(context),
              onPressed:
                  busy ||
                      detail.isLoading ||
                      detail.hasError ||
                      detail.asData?.value == null ||
                      _payment.validation(quote.pricePaise) != null
                  ? null
                  : () => _confirm(quote),
              child: const Text('Confirm Renewal'),
            ),
          ],
          TextButton(
            onPressed: busy
                ? null
                : () => ref.invalidate(
                    selectedRenewalPreviewProvider(_previewRequest),
                  ),
            child: const Text('Refresh price and dates'),
          ),
        ],
        if (_step > 0)
          TextButton(
            onPressed: busy ? null : () => setState(() => _step--),
            child: const Text('Back'),
          ),
      ],
      if (busy)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: LinearProgressIndicator(),
        ),
      if (confirmed == null)
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
    ];
    return PopScope(
      canPop: !busy,
      child: TitaniumGlass(
        opacity: .96,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
