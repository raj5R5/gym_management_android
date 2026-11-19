import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/navigation/foundation_screens.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/contact/member_contact.dart';
import '../../shared/formatting/inr.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/page_section.dart';
import '../gym_settings/gym_settings.dart';
import '../receipts/receipt.dart';
import '../visits/visit_models.dart';
import 'member_home.dart';

String _date(BuildContext context, DateTime day) =>
    MaterialLocalizations.of(context).formatMediumDate(day);

/// Headline for the membership card: what the member needs to know first.
({String title, String detail, bool warn}) membershipHeadline(
  MemberHomeMembership? membership,
  String Function(DateTime) date,
) {
  if (membership == null) {
    return (
      title: 'No membership yet',
      detail: 'Ask at the front desk to start a plan.',
      warn: true,
    );
  }
  if (membership.frozenUntil != null) {
    return (
      title: 'Frozen',
      detail:
          'Paused until ${date(membership.frozenUntil!.subtract(const Duration(days: 1)))}. '
          'Your end date moves by the days paused.',
      warn: false,
    );
  }
  switch (membership.state) {
    case 'upcoming':
      return (
        title: 'Starts ${date(membership.startDate)}',
        detail: 'Valid until ${date(membership.lastDay)}.',
        warn: false,
      );
    case 'expired':
      final ago = membership.daysSinceExpiry;
      return (
        title: 'Expired',
        detail:
            'Ended ${ago <= 1 ? (ago == 0 ? 'today' : 'yesterday') : '$ago days ago'}. '
            'Renew at the front desk to keep training.',
        warn: true,
      );
    default:
      final left = membership.daysLeft;
      return (
        title: '$left day${left == 1 ? '' : 's'} left',
        detail: membership.renewedAhead
            ? 'Valid until ${date(membership.lastDay)}. Next plan already booked.'
            : membership.expiringSoon
            ? 'Ends ${date(membership.lastDay)}. Renew soon to avoid a break.'
            : 'Valid until ${date(membership.lastDay)}.',
        warn: membership.expiringSoon && !membership.renewedAhead,
      );
  }
}

class MemberHomePage extends ConsumerWidget {
  const MemberHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(memberHomeProvider);
    final home = state.asData?.value;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(memberHomeProvider);
            ref.invalidate(memberPaymentsProvider);
            ref.invalidate(memberClaimsProvider);
            await ref.read(memberHomeProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          home == null ? 'Welcome' : 'Hi ${home.firstName}',
                          style: theme.textTheme.headlineSmall,
                        ),
                        if (home != null)
                          Text(
                            '${home.gymName} · ${home.memberCode}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Account',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: SafeArea(child: AuthenticatedHomeScreen()),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (home == null && state.hasError)
                GlassCard(
                  child: Column(
                    children: [
                      Text(
                        state.error is MemberAppFailure
                            ? (state.error! as MemberAppFailure).message
                            : 'Your details could not be loaded.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(memberHomeProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (home == null)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _MembershipCard(home: home),
                _CheckInCard(home: home),
                _VisitsCard(home: home),
                if (home.pt.isNotEmpty) _PtCard(home: home),
                const _PaymentsCard(),
                _GymCard(home: home),
                const SizedBox(height: AppSpacing.xl),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.home});
  final MemberHome home;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = membershipHeadline(
      home.membership,
      (day) => _date(context, day),
    );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            home.membership?.planName ?? 'Membership',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            headline.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: headline.warn ? AppPalette.amber : null,
            ),
          ),
          Text(headline.detail, style: theme.textTheme.bodyMedium),
          if (home.balancePaise > 0) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppPalette.amber,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${formatInrPaise(home.balancePaise)} due',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppPalette.amber,
                    ),
                  ),
                ),
              ],
            ),
            _DuesActions(home: home),
          ],
        ],
      ),
    );
  }
}

class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.home});
  final MemberHome home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gymId = ref.watch(memberGymIdProvider) ?? '';
    return PageSection(
      title: 'Check-in code',
      trailing: home.visitedToday
          ? const Chip(
              avatar: Icon(Icons.check, size: 16),
              label: Text('In today'),
            )
          : null,
      children: [
        // A white quiet zone keeps the code scannable on the dark theme.
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SizedBox.square(
              dimension: 200,
              child: QrImageView(
                data: MemberQrCode.encode(
                  gymId: gymId,
                  memberId: home.memberId,
                ),
                semanticsLabel: 'Check-in code for ${home.memberCode}',
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Show this at the front desk to check in.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _VisitsCard extends StatelessWidget {
  const _VisitsCard({required this.home});
  final MemberHome home;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = home.lastVisit;
    return PageSection(
      title: 'Your visits',
      children: [
        Row(
          children: [
            Expanded(
              child: _Figure(
                value: '${home.visitsThisMonth}',
                label: 'This month',
              ),
            ),
            Expanded(
              child: _Figure(
                value: '${home.weekStreak}',
                label: home.weekStreak == 1 ? 'Week streak' : 'Weeks streak',
              ),
            ),
            Expanded(
              child: _Figure(
                value: last == null
                    ? '–'
                    : home.visitedToday
                    ? 'Today'
                    : MaterialLocalizations.of(
                        context,
                      ).formatShortMonthDay(last),
                label: 'Last visit',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          home.weekStreak == 0
              ? 'Visit this week to start a streak.'
              : 'Train at least once a week to keep your streak.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PtCard extends StatelessWidget {
  const _PtCard({required this.home});
  final MemberHome home;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageSection(
      title: 'Personal training',
      children: [
        for (final pkg in home.pt) ...[
          if (pkg != home.pt.first) const SizedBox(height: AppSpacing.lg),
          Text(
            pkg.trainerName == null
                ? pkg.name
                : '${pkg.name} · ${pkg.trainerName}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: pkg.sessionsTotal == 0
                  ? 0
                  : 1 - pkg.sessionsLeft / pkg.sessionsTotal,
            ),
          ),
          Text(
            [
              '${pkg.sessionsLeft} of ${pkg.sessionsTotal} sessions left',
              if (pkg.expired)
                'expired'
              else if (pkg.expiresOn != null)
                'use by ${MaterialLocalizations.of(context).formatShortMonthDay(pkg.expiresOn!.subtract(const Duration(days: 1)))}',
              if (pkg.balancePaise > 0)
                '${formatInrPaise(pkg.balancePaise)} due',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PaymentsCard extends ConsumerWidget {
  const _PaymentsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(memberPaymentsProvider);
    final rows = state.asData?.value;
    final gymId = ref.watch(memberGymIdProvider);
    return PageSection(
      title: 'Payments',
      children: [
        if (state.hasError && rows == null)
          Text(
            'Payments could not be loaded.',
            style: theme.textTheme.bodySmall,
          )
        else if (rows == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (rows.isEmpty)
          Text('No payments yet.', style: theme.textTheme.bodySmall)
        else
          SeparatedRows(
            children: [
              for (final payment in rows.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(formatInrPaise(payment.amountPaise)),
                  subtitle: Text(
                    '${_date(context, payment.paidAt)} · ${payment.method.replaceAll('_', ' ')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Receipt',
                    onPressed: gymId == null
                        ? null
                        : () => shareReceipt(
                            context,
                            ref,
                            payment.id,
                            memberGymId: gymId,
                          ),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _GymCard extends StatelessWidget {
  const _GymCard({required this.home});
  final MemberHome home;
  @override
  Widget build(BuildContext context) {
    return PageSection(
      title: home.gymName,
      subtitle: home.gymAddress,
      children: [
        if (home.gymPhone != null)
          OutlinedButton.icon(
            onPressed: () => callMember(context, home.gymPhone!),
            icon: const Icon(Icons.call_outlined),
            label: const Text('Call the gym'),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.headlineSmall),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Pay by UPI and report it, or pay at the desk when the gym has no UPI ID.
class _DuesActions extends ConsumerWidget {
  const _DuesActions({required this.home});
  final MemberHome home;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reported = await showDialog<bool>(
      context: context,
      builder: (_) => ReportUpiDialog(maxPaise: home.claimablePaise),
    );
    if (reported == true && context.mounted) {
      ref
        ..invalidate(memberHomeProvider)
        ..invalidate(memberClaimsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sent to the gym. It shows as paid once they confirm.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final upiId = home.upiId;
    final rejected = recentRejection(
      ref.watch(memberClaimsProvider).asData?.value,
      DateTime.now(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rejected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Your ${formatInrPaise(rejected.amountPaise)} UPI report was not accepted'
              '${rejected.rejectReason == null ? '' : ': ${rejected.rejectReason}'}. '
              'Ask at the front desk if you did pay.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.amber,
              ),
            ),
          ),
        if (home.pendingClaimPaise > 0)
          Text(
            '${formatInrPaise(home.pendingClaimPaise)} reported by you, waiting for the gym to confirm.',
            style: theme.textTheme.bodySmall,
          ),
        if (home.claimablePaise > 0 && upiId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () async {
              await openExternal(
                context,
                Uri.parse(
                  upiPayUri(
                    upiId: upiId,
                    payeeName: home.upiPayeeName ?? home.gymName,
                    amountPaise: home.claimablePaise,
                    note: 'Membership ${home.memberCode}',
                  ),
                ),
                'No UPI app found on this phone.',
              );
              if (context.mounted) await _report(context, ref);
            },
            icon: const Icon(Icons.qr_code_2),
            label: Text('Pay ${formatInrPaise(home.claimablePaise)} by UPI'),
          ),
          TextButton(
            onPressed: () => _report(context, ref),
            child: const Text('Already paid by UPI? Report it'),
          ),
        ] else if (home.claimablePaise > 0)
          Text('Pay at the front desk.', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Asks for the amount and the 12-digit UPI transaction ID; pops true once sent.
class ReportUpiDialog extends ConsumerStatefulWidget {
  const ReportUpiDialog({super.key, required this.maxPaise});
  final int maxPaise;
  @override
  ConsumerState<ReportUpiDialog> createState() => _ReportUpiDialogState();
}

class _ReportUpiDialogState extends ConsumerState<ReportUpiDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.maxPaise % 100 == 0
        ? '${widget.maxPaise ~/ 100}'
        : (widget.maxPaise / 100).toStringAsFixed(2),
  );
  final _reference = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  int? get _paise {
    final match = RegExp(
      r'^(\d{1,8})(?:\.(\d{1,2}))?$',
    ).firstMatch(_amount.text.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) * 100 +
        int.parse((match.group(2) ?? '0').padRight(2, '0'));
  }

  Future<void> _send() async {
    final gymId = ref.read(memberGymIdProvider);
    if (gymId == null || _busy || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(memberHomeRepositoryProvider)
          .reportUpiPayment(
            gymId,
            amountPaise: _paise!,
            reference: _reference.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on MemberAppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report UPI payment'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Find the 12-digit UPI transaction ID (UTR) in your UPI app's payment details.",
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('upi-amount'),
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount paid',
                prefixText: '₹',
              ),
              validator: (_) {
                final paise = _paise;
                if (paise == null || paise < 1) return 'Enter the amount';
                return paise > widget.maxPaise
                    ? 'More than the ${formatInrPaise(widget.maxPaise)} due'
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const ValueKey('upi-reference'),
              controller: _reference,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'UPI transaction ID',
                counterText: '',
              ),
              validator: (value) => RegExp(r'^\d{12}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter all 12 digits',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Not now'),
      ),
      FilledButton(
        onPressed: _busy ? null : _send,
        child: Text(_busy ? 'Sending…' : 'Send to gym'),
      ),
    ],
  );
}
