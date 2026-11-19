import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';
import '../members/providers/member_overview_providers.dart';
import 'member_home.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/page_section.dart';
import '../../shared/widgets/card_reveal.dart';

/// A member's "I paid by UPI" report, waiting for the owner.
class PaymentClaim {
  PaymentClaim.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      amountPaise = json['amountPaise'] as int,
      reference = json['reference'] as String,
      createdAt = DateTime.parse(json['createdAt'] as String).toLocal(),
      planName = json['planName'] as String?,
      memberName = (json['member'] as Map?)?['name'] as String? ?? 'Member',
      memberCode = (json['member'] as Map?)?['memberCode'] as String? ?? '';
  final String id, reference, memberName, memberCode;
  final String? planName;
  final int amountPaise;
  final DateTime createdAt;
}

class PaymentClaimRepository {
  PaymentClaimRepository(this._client);
  final Dio _client;

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const MemberAppFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw MemberAppFailure(switch (code) {
        'CLAIM_ALREADY_DECIDED' =>
          'This payment was already confirmed or rejected.',
        'CLAIM_NOT_FOUND' => 'This payment report is no longer available.',
        'PAYMENT_OVERPAYMENT' =>
          'This would be more than the amount due. Check payments recorded at the desk, then reject it.',
        'PAYMENT_SUBSCRIPTION_CANCELLED' =>
          'That membership was cancelled. Reject this report.',
        'DUPLICATE_PAYMENT_REFERENCE' || 'DUPLICATE_TRANSACTION_REFERENCE' =>
          'A payment with this UPI transaction ID is already recorded.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on TypeError {
      throw const MemberAppFailure('The server returned unexpected data.');
    }
  }

  Future<List<PaymentClaim>> pending(String gymId) => _call(
    () => _client.get<dynamic>('gyms/$gymId/payment-claims'),
    (data) => [
      for (final row in data as List)
        PaymentClaim.fromJson(row as Map<String, dynamic>),
    ],
  );

  Future<void> confirm(String gymId, String claimId) => _call(
    () => _client.post<dynamic>('gyms/$gymId/payment-claims/$claimId/confirm'),
    (_) {},
  );

  Future<void> reject(String gymId, String claimId, String reason) => _call(
    () => _client.post<dynamic>(
      'gyms/$gymId/payment-claims/$claimId/reject',
      data: {'reason': reason},
    ),
    (_) {},
  );
}

final paymentClaimRepositoryProvider = Provider<PaymentClaimRepository>(
  (ref) => PaymentClaimRepository(ref.watch(authenticatedApiClientProvider)),
);

final pendingClaimsProvider = FutureProvider.autoDispose<List<PaymentClaim>?>((
  ref,
) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(paymentClaimRepositoryProvider).pending(gym.gymId);
}, retry: (_, _) => null);

/// Dashboard prompt; hidden when nothing waits (or the list cannot load).
class PendingClaimsBanner extends ConsumerWidget {
  const PendingClaimsBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(pendingClaimsProvider).asData?.value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    final total = rows.fold<int>(0, (sum, row) => sum + row.amountPaise);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(
            Icons.mark_email_unread_outlined,
            color: AppPalette.amber,
          ),
          title: Text(
            '${rows.length} UPI payment${rows.length == 1 ? '' : 's'} to confirm',
          ),
          subtitle: Text('${formatInrPaise(total)} reported by members'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => pushFromCard(context, AppRoutes.paymentClaims),
        ),
      ),
    );
  }
}

class PaymentClaimsPage extends ConsumerStatefulWidget {
  const PaymentClaimsPage({super.key});
  @override
  ConsumerState<PaymentClaimsPage> createState() => _PaymentClaimsPageState();
}

class _PaymentClaimsPageState extends ConsumerState<PaymentClaimsPage> {
  final _busy = <String>{};

  Future<void> _decide(
    PaymentClaim claim,
    Future<void> Function(String gymId) action,
    String done,
  ) async {
    final gym = ref.read(adminGymProvider);
    if (gym == null || _busy.contains(claim.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy.add(claim.id));
    try {
      await action(gym.gymId);
      container
        ..invalidate(pendingClaimsProvider)
        ..invalidate(dashboardProvider)
        ..invalidate(memberOverviewProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on MemberAppFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(claim.id));
    }
  }

  Future<void> _reject(PaymentClaim claim) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || reason.isEmpty) return;
    await _decide(
      claim,
      (gymId) => ref
          .read(paymentClaimRepositoryProvider)
          .reject(gymId, claim.id, reason),
      'Rejected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(pendingClaimsProvider);
    final rows = state.asData?.value;
    final localizations = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                'UPI payments to confirm',
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        Text(
          'Check each amount and transaction ID in your bank or UPI app before '
          'confirming. Confirming records the payment and its receipt.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (state.hasError && rows == null)
          PlainBlock(
            child: Column(
              children: [
                Text(
                  state.error is MemberAppFailure
                      ? (state.error! as MemberAppFailure).message
                      : 'Reports could not be loaded.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(pendingClaimsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (rows == null)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          const PlainBlock(child: Text('Nothing to confirm right now.'))
        else
          for (final claim in rows) ...[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          claim.memberName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        formatInrPaise(claim.amountPaise),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  Text(
                    [
                      claim.memberCode,
                      ?claim.planName,
                      '${localizations.formatShortMonthDay(claim.createdAt)}, '
                          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(claim.createdAt))}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    'UPI transaction ID ${claim.reference}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy.contains(claim.id)
                              ? null
                              : () => _reject(claim),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy.contains(claim.id)
                              ? null
                              : () => _decide(
                                  claim,
                                  (gymId) => ref
                                      .read(paymentClaimRepositoryProvider)
                                      .confirm(gymId, claim.id),
                                  '${formatInrPaise(claim.amountPaise)} recorded for ${claim.memberName}',
                                ),
                          child: const Text('Confirm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConfirmDialog(
    title: 'Reject this payment?',
    message: 'No payment is recorded. The member sees your reason.',
    keepLabel: 'Keep pending',
    confirmLabel: 'Reject payment',
    destructive: true,
    onKeep: () => Navigator.pop(context),
    onConfirm: () => Navigator.pop(context, _reason.text.trim()),
    content: TextField(
      key: const ValueKey('claim-reject-reason'),
      controller: _reason,
      autofocus: true,
      maxLength: 200,
      decoration: const InputDecoration(
        labelText: 'Reason',
        hintText: 'Not received in our account',
      ),
    ),
  );
}
