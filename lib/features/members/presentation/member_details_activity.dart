import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/page_section.dart';
import '../../member_app/member_access.dart';
import '../../memberships/data/billing_failure.dart';
import '../../memberships/data/outstanding_dues_repository.dart';
import '../../memberships/models/membership_eligibility.dart';
import '../../memberships/presentation/billing_components.dart';
import '../../personal_training/pt.dart';
import '../../personal_training/pt_widgets.dart';
import '../../visits/member_visit_widgets.dart';
import '../../visits/visit_repository.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_details_cards.dart';

/// Every unpaid amount across the member's memberships, once the server
/// records are verified; null while they are not.
int? verifiedDuesPaise(MemberProfile member, List<Membership>? records) {
  if (records == null) return null;
  try {
    return OutstandingDues([
      OutstandingMember(member, verifiedUnpaidMemberships(records)),
    ]).totalPaise;
  } on BillingFailure {
    return null;
  } on FormatException {
    return null;
  }
}

/// Calendar days from [today] to a membership's exclusive end date.
int membershipDaysLeft(Membership membership, DateTime today) {
  DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  return day(membership.endDate.value).difference(day(today)).inDays;
}

enum _Tone { danger, warning, good, neutral }

/// One sentence that says where this member stands right now, before any
/// detail: money owed first, then time left, coloured by urgency.
class MemberStatusLine extends ConsumerWidget {
  const MemberStatusLine({
    super.key,
    required this.scope,
    required this.summary,
    this.today,
  });
  final MemberScope scope;
  final MemberSummary summary;

  /// For tests; defaults to the device's calendar day.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final state = ref.watch(memberMembershipsProvider(scope));
    final verified =
        !state.isLoading && !state.hasError && state.asData?.value != null;
    final dues = verified
        ? verifiedDuesPaise(summary.member, state.asData!.value!)
        : null;
    final membership = summary.currentSubscription;
    final previous = summary.history.firstOrNull;
    final left = membership == null
        ? null
        : membershipDaysLeft(membership, today ?? DateTime.now());
    final lastDay = membership?.endDate.value.subtract(const Duration(days: 1));
    final timeText = left == null
        ? (previous?.status == 'expired'
              ? 'Membership expired'
              : 'No active membership')
        : left <= 1
        ? 'Last day today'
        : '$left days left · ends ${dates.formatShortMonthDay(lastDay!)}';

    final (
      String headline,
      String? detail,
      _Tone tone,
      IconData icon,
    ) = switch ((dues, left)) {
      (final owed?, _) when owed > 0 => (
        '${formatInrPaise(owed)} due',
        timeText,
        _Tone.danger,
        Icons.account_balance_wallet_outlined,
      ),
      (_, null) => (
        timeText,
        previous?.status == 'expired'
            ? 'Renew to keep training.'
            : 'Choose a plan to start.',
        previous?.status == 'expired' ? _Tone.danger : _Tone.neutral,
        Icons.event_busy_outlined,
      ),
      (_, final days?) when days <= 7 => (
        days <= 1 ? 'Last day today' : 'Ends in $days days',
        dues == 0 ? 'All paid. Time to renew.' : 'Time to renew.',
        _Tone.warning,
        Icons.hourglass_bottom,
      ),
      (0, _) => ('All paid', timeText, _Tone.good, Icons.check_circle_outline),
      _ => (timeText, null, _Tone.neutral, Icons.event_available_outlined),
    };
    final color = switch (tone) {
      _Tone.danger => AppPalette.accentLight,
      _Tone.warning => AppPalette.amber,
      _Tone.good => theme.colorScheme.primary,
      _Tone.neutral => theme.colorScheme.onSurfaceVariant,
    };
    final wash = switch (tone) {
      _Tone.danger => AppPalette.warningWash,
      _Tone.warning => AppPalette.amberWash,
      _ => AppColors.glass,
    };
    return Semantics(
      container: true,
      label: [headline, ?detail].join('. '),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('member-status-line'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tone == _Tone.neutral ? null : color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null)
                    Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visits, payments, personal training and app access as one list of rows,
/// each with a one-line summary; a tap opens the full detail.
class MemberActivityList extends ConsumerWidget {
  const MemberActivityList({
    super.key,
    required this.scope,
    required this.summary,
    this.timezone,
  });
  final MemberScope scope;
  final MemberSummary summary;

  /// The gym's verified timezone, for payment times.
  final String? timezone;

  Future<void> _sheet(BuildContext context, Widget child) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            // Each detail card carries its own heading.
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = summary.member;
    final payments = summary.payments;
    final visits = ref.watch(memberVisitHistoryProvider(member.id));
    final visitText = switch (visits) {
      AsyncData(:final value?) =>
        '${value.lastVisitLabel} · ${value.visitsLast30Days} in 30 days',
      AsyncError() => 'Could not load visits',
      _ => 'Loading…',
    };
    final pt = ref.watch(
      ptPackagesProvider((memberId: member.id, trainerId: null, status: null)),
    );
    final ptText = switch (pt) {
      AsyncData(:final value?) => () {
        final active = value.where((pkg) => pkg.status == PtStatus.active);
        if (value.isEmpty) return 'No packages';
        if (active.isEmpty) return 'No active package';
        final left = active.fold<int>(0, (sum, pkg) => sum + pkg.sessionsLeft);
        return '${active.length} active · $left sessions left';
      }(),
      AsyncError() => 'Could not load packages',
      _ => 'Loading…',
    };
    final access = ref.watch(
      memberAccessProvider((gymId: scope.gymId, memberId: member.id)),
    );
    final accessText = switch (access) {
      AsyncData(value: MemberAccessState(provisioned: false)) => 'Not set up',
      AsyncData(value: MemberAccessState(accessActive: false)) => 'Turned off',
      AsyncData(value: MemberAccessState(activated: false)) =>
        'Waiting for activation',
      AsyncData() => 'On',
      AsyncError() => 'Could not load',
      _ => 'Loading…',
    };
    final ptMember = PtPerson.fromJson({
      'id': member.id,
      'name': member.name,
      'memberCode': member.memberCode,
    });
    return ProfileSection(
      title: 'Activity',
      children: [
        SeparatedRows(
          indent: 40,
          children: [
            _ActivityRow(
              icon: Icons.event_available_outlined,
              title: 'Visits',
              subtitle: visitText,
              onTap: () => _sheet(context, MemberVisitsCard(member: member)),
            ),
            _ActivityRow(
              key: const ValueKey('member-payments-row'),
              icon: Icons.receipt_long_outlined,
              title: 'Payments',
              subtitle:
                  'Total paid ${formatInrPaise(payments.totalPaise)} · ${payments.count} ${payments.count == 1 ? 'payment' : 'payments'}',
              extra: MemberLatestPayment(
                payments: payments,
                timezone: timezone,
                compact: true,
              ),
              onTap: () => context.push(membershipPath(scope)),
            ),
            _ActivityRow(
              icon: Icons.sports_gymnastics_outlined,
              title: 'Personal training',
              subtitle: ptText,
              onTap: () => _sheet(context, MemberPtCard(member: ptMember)),
            ),
            _ActivityRow(
              icon: Icons.phone_iphone_outlined,
              title: 'Member app',
              subtitle: accessText,
              onTap: () => _sheet(
                context,
                MemberAppAccessCard(gymId: scope.gymId, member: member),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.extra,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  /// A second line under the summary.
  final Widget? extra;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: extra == null
        ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              extra!,
            ],
          ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
