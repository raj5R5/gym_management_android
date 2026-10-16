import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../data/billing_failure.dart';
import '../models/billing_models.dart';
import '../providers/membership_providers.dart';
import 'billing_components.dart';

Future<BillingResult?> showCancellationConfirmation(
  BuildContext context,
  MembershipRequest request,
) => showModalBottomSheet<BillingResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => CancellationConfirmationSheet(request: request),
);

class CancellationConfirmationSheet extends ConsumerStatefulWidget {
  const CancellationConfirmationSheet({super.key, required this.request});
  final MembershipRequest request;

  @override
  ConsumerState<CancellationConfirmationSheet> createState() =>
      _CancellationConfirmationSheetState();
}

class _CancellationConfirmationSheetState
    extends ConsumerState<CancellationConfirmationSheet> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final AuthRepository _auth;
  late final int _revision;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authRepositoryProvider);
    _revision = _auth.revision;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool _current() =>
      mounted &&
      matchesScope(ref.read(adminGymProvider), widget.request.scope) &&
      identical(ref.read(authRepositoryProvider), _auth) &&
      _auth.revision == _revision;

  // This is a response consistency check, not a client calculation of dues.
  // Display only the backend's saved membership-specific payment summary.
  bool _verified(MemberProfile? member, MembershipDetail? detail) =>
      member != null &&
      detail != null &&
      member.id == widget.request.scope.memberId &&
      member.gymId == widget.request.scope.gymId &&
      detail.subscription.id == widget.request.subscriptionId &&
      detail.payments.paidPaise + detail.payments.balancePaise ==
          detail.subscription.pricePaise;

  void _reload() {
    ref.invalidate(memberProfileProvider(widget.request.scope));
    ref.invalidate(membershipDetailProvider(widget.request));
  }

  Future<void> _confirm() async {
    if (_sending || !_current() || !_form.currentState!.validate()) return;
    // Recheck live provider values: stale AsyncData during refresh cannot confirm.
    final profile = ref.read(memberProfileProvider(widget.request.scope));
    final detail = ref.read(membershipDetailProvider(widget.request));
    if (profile.isLoading ||
        profile.hasError ||
        detail.isLoading ||
        detail.hasError ||
        !_verified(profile.asData?.value, detail.asData?.value) ||
        detail.asData!.value!.subscription.status == 'cancelled') {
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(billingMutationProvider(widget.request.scope).notifier)
        .cancel(widget.request.subscriptionId, _reason.text);
    if (!mounted) return;
    if (_current() && result != null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(adminGymProvider);
    final current = _current();
    final profile = ref.watch(memberProfileProvider(widget.request.scope));
    final detail = ref.watch(membershipDetailProvider(widget.request));
    final mutation = ref.watch(billingMutationProvider(widget.request.scope));
    final busy = _sending || mutation.isLoading;
    final blocked =
        mutation.error is BillingFailure &&
        (mutation.error! as BillingFailure).uncertain;
    final loading = profile.isLoading || detail.isLoading;
    final failed = profile.hasError || detail.hasError;
    final member = !loading && !failed ? profile.asData?.value : null;
    final data = !loading && !failed ? detail.asData?.value : null;
    final verified = _verified(member, data);
    final cancelled = data?.subscription.status == 'cancelled';
    final canConfirm = current && verified && !cancelled && !busy && !blocked;
    return PopScope(
      canPop: !busy,
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
              children: [
                Text(
                  'Cancel membership?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!current)
                  const Text(
                    'The account or gym changed. Close this confirmation and reopen the correct membership.',
                  )
                else if (loading) ...[
                  const LinearProgressIndicator(),
                  const Text('Checking membership details and saved balance…'),
                ] else if (failed)
                  BillingError(
                    error: detail.hasError ? detail.error : profile.error,
                    retry: busy ? null : _reload,
                  )
                else if (!verified) ...[
                  const Text(
                    'The membership balance or member details could not be verified. Reload before cancelling.',
                  ),
                  TextButton(
                    onPressed: busy ? null : _reload,
                    child: const Text('Retry'),
                  ),
                ] else ...[
                  SoftPanel(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text('Member code: ${member.memberCode}'),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          data!.subscription.planName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Status: ${switch (data.subscription.status) {
                            'active' => 'Active',
                            'expired' => 'Expired',
                            _ => 'Cancelled',
                          }}',
                        ),
                        Text(
                          'End date: ${MaterialLocalizations.of(context).formatMediumDate(data.subscription.endDate.value)}',
                        ),
                        const Text(
                          'End date is exclusive. Membership calendar dates use UTC.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SoftPanel(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    tone: AppTone.pending,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Outstanding balance',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          formatInrPaise(data.payments.balancePaise),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          'Total paid: ${formatInrPaise(data.payments.paidPaise)}',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          data.payments.balancePaise == 0
                              ? 'This membership is fully paid. There is no unpaid balance to collect.'
                              : 'The unpaid ${formatInrPaise(data.payments.balancePaise)} remains in this membership’s history. Cancellation does not collect, waive or delete it.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'Membership and payment history will be kept. No refund is created.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Cancelled memberships are excluded from current outstanding dues. You cannot record any further payments against this membership.',
                  ),
                  if (cancelled)
                    const Text(
                      'This membership is already cancelled. No further cancellation is needed.',
                    ),
                  if (!cancelled) ...[
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      key: const ValueKey('cancellationReason'),
                      controller: _reason,
                      enabled: !busy && !blocked,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional)',
                      ),
                      validator: (value) => (value ?? '').trim().length > 500
                          ? 'Use at most 500 characters for the reason.'
                          : null,
                    ),
                  ],
                ],
                if (current && mutation.hasError)
                  BillingError(error: mutation.error),
                if (current && blocked)
                  const Text(
                    'Cancellation could not be confirmed. Do not submit again. Close this confirmation and check membership and payment history.',
                  ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Keep Membership'),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  style: AppButtonStyles.warning(context),
                  onPressed: canConfirm ? _confirm : null,
                  child: Text(
                    busy ? 'Cancelling membership…' : 'Confirm Cancellation',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
