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
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_list_widgets.dart'
    show membershipStatusLabel;
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/payment_providers.dart';
import 'billing_components.dart';
import 'payment_transaction_details.dart';

Future<RecordedPayment?> showRecordPayment(
  BuildContext context,
  PaymentScope scope,
  String? memberName, {
  String? memberCode,
}) => showModalBottomSheet<RecordedPayment>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  showDragHandle: false,
  builder: (_) => RecordPaymentSheet(
    scope: scope,
    memberName: memberName,
    memberCode: memberCode,
  ),
);

class RecordPaymentSheet extends ConsumerStatefulWidget {
  const RecordPaymentSheet({
    super.key,
    required this.scope,
    required this.memberName,
    this.memberCode,
  });
  final PaymentScope scope;
  final String? memberName, memberCode;
  @override
  ConsumerState<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<RecordPaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!matchesScope(ref.watch(adminGymProvider), widget.scope.member)) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'The account or gym changed. Close this form and reopen the correct membership.',
        ),
      );
    }
    final gym = ref.watch(adminGymProvider)!;
    final timezone = ref.watch(paymentTimezoneProvider(gym)).asData?.value;
    final request = (
      scope: widget.scope.member,
      subscriptionId: widget.scope.subscriptionId,
    );
    final detail = ref.watch(membershipDetailProvider(request));
    final profile = ref.watch(memberProfileProvider(widget.scope.member));
    final member = profile.asData?.value;
    final mutation = ref.watch(paymentCollectionProvider(widget.scope));
    final controller = ref.read(
      paymentCollectionProvider(widget.scope).notifier,
    );
    final busy = mutation.isLoading || controller.busy;
    final blocked =
        controller.blocked ||
        (mutation.error is BillingFailure &&
            (mutation.error! as BillingFailure).uncertain);
    final data = detail.isLoading || detail.hasError
        ? null
        : detail.asData?.value;
    final eligible =
        data != null &&
        data.subscription.status != 'cancelled' &&
        data.payments.balancePaise > 0;
    final result = controller.confirmed;
    final saved = controller.savedCollection;
    return PopScope(
      canPop: !busy,
      child: TitaniumGlass(
        opacity: .96,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Record Payment',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    member?.name ??
                        widget.memberName ??
                        'Member details unavailable',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if ((member?.memberCode ?? widget.memberCode)
                      case final code?)
                    IconLabel('Member code: $code', icon: Icons.badge_outlined),
                  if (profile.isLoading)
                    const LinearProgressIndicator()
                  else if (profile.hasError)
                    BillingError(
                      error: profile.error,
                      retry: () => ref.invalidate(
                        memberProfileProvider(widget.scope.member),
                      ),
                    ),
                  if (detail.isLoading)
                    const LinearProgressIndicator()
                  else if (detail.hasError)
                    BillingError(
                      error: detail.error,
                      retry: () =>
                          ref.invalidate(membershipDetailProvider(request)),
                    )
                  else if (data != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    SoftPanel(
                      tone: AppTone.payment,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.subscription.planName),
                          Text(
                            'Remaining balance: ${formatInrPaise(data.payments.balancePaise)}',
                          ),
                          Text(
                            'Membership: ${membershipStatusLabel(data.subscription)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Payment recorded',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    PaymentTransactionDetails(
                      payment: result,
                      timezone: timezone,
                    ),
                    if (mutation.hasError) BillingError(error: mutation.error),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await controller.acknowledge();
                              if (!context.mounted ||
                                  controller.hasSavedOperation ||
                                  !matchesScope(
                                    ref.read(adminGymProvider),
                                    widget.scope.member,
                                  )) {
                                return;
                              }
                              Navigator.of(context).pop(result);
                            },
                      child: const Text('Done'),
                    ),
                    if (eligible)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await controller.startAnother();
                                if (!mounted ||
                                    controller.hasSavedOperation ||
                                    !matchesScope(
                                      ref.read(adminGymProvider),
                                      widget.scope.member,
                                    )) {
                                  return;
                                }
                                _amount.clear();
                                _reference.clear();
                                setState(() => _method = PaymentMethod.cash);
                              },
                        child: const Text('Record another installment'),
                      ),
                  ] else ...[
                    const SizedBox(height: AppSpacing.lg),
                    if (!eligible && data != null)
                      const Text('This membership has no collectible balance.'),
                    TextFormField(
                      key: const Key('collection-amount'),
                      controller: _amount,
                      enabled: eligible && !busy && !blocked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        prefixIcon: FieldIcon('amount'),
                        labelText: 'Amount received (₹)',
                      ),
                      validator: (value) {
                        try {
                          final amount = parsePaymentRupees(value ?? '');
                          return data == null ||
                                  amount > data.payments.balancePaise
                              ? 'Payment cannot exceed the remaining balance.'
                              : null;
                        } on FormatException catch (error) {
                          return error.message;
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<PaymentMethod>(
                      itemHeight: null,
                      initialValue: _method,
                      decoration: const InputDecoration(
                        prefixIcon: FieldIcon('method'),
                        labelText: 'Payment method',
                      ),
                      isExpanded: true,
                      items: [
                        for (final method in PaymentMethod.values)
                          DropdownMenuItem(
                            value: method,
                            child: Text(method.label),
                          ),
                      ],
                      onChanged: !eligible || busy || blocked
                          ? null
                          : (value) => setState(() => _method = value!),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('collection-reference'),
                      controller: _reference,
                      enabled: eligible && !busy && !blocked,
                      decoration: InputDecoration(
                        prefixIcon: const FieldIcon('reference'),
                        labelText: _method.requiresReference
                            ? 'Payment reference'
                            : 'Reference (optional)',
                      ),
                      validator: (value) =>
                          paymentReferenceError(_method, value ?? ''),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Record money already received. This creates an auditable backend payment receipt.',
                    ),
                    if (mutation.hasError) BillingError(error: mutation.error),
                    if (blocked) ...[
                      if (busy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Checking saved payment',
                        ),
                      if (saved != null)
                        SoftPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Saved payment awaiting confirmation'),
                              IconLabel(
                                'Amount: ${formatInrPaise(saved.body['amountPaise'] as int)}',
                                icon: Icons.payments_outlined,
                              ),
                              IconLabel(
                                'Method: ${PaymentMethod.values.firstWhere((method) => method.wireValue == saved.body['paymentMethod']).label}',
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              if (saved.body['transactionReference'] != null)
                                IconLabel(
                                  'Reference: ${saved.body['transactionReference']}',
                                  icon: Icons.receipt_long_outlined,
                                ),
                            ],
                          ),
                        ),
                      const Text(
                        'The saved payment remains unresolved. Do not collect or enter it again. Exact retry reuses its original amount, time and key.',
                      ),
                      if (controller.canRetry)
                        FilledButton(
                          onPressed: busy ? null : controller.retrySaved,
                          child: const Text('Retry saved payment'),
                        ),
                      OutlinedButton(
                        onPressed: busy ? null : controller.recheck,
                        child: const Text('Recheck saved payment'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () {
                                ref.invalidate(
                                  membershipDetailProvider(request),
                                );
                              },
                        child: const Text('Refresh membership balance'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () {
                                final router = GoRouter.of(context);
                                Navigator.of(context).pop();
                                router.push(
                                  membershipPath(widget.scope.member),
                                );
                              },
                        child: const Text('View payment history'),
                      ),
                    ] else
                      FilledButton(
                        style: AppButtonStyles.primary(context),
                        onPressed: !eligible || busy
                            ? null
                            : () async {
                                if (!_form.currentState!.validate()) return;
                                final payment = ManualPayment(
                                  amountPaise: parsePaymentRupees(_amount.text),
                                  method: _method,
                                  paidAt: DateTime.now().toUtc(),
                                  reference: _reference.text,
                                );
                                await controller.collect(
                                  payment,
                                  data.payments.balancePaise,
                                );
                              },
                        child: Text(
                          busy ? 'Recording payment…' : 'Confirm payment',
                        ),
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
