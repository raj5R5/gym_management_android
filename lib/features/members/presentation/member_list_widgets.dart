import '../photos/member_photo_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/formatting/inr.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../models/member_models.dart';

String memberStatusLabel(MemberStatus status) => switch (status) {
  MemberStatus.active => 'Active',
  MemberStatus.inactive => 'Inactive',
  MemberStatus.suspended => 'Suspended',
};

class MemberStatusBadge extends StatelessWidget {
  const MemberStatusBadge({super.key, required this.status});
  final MemberStatus status;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final color = switch (status) {
      MemberStatus.active => surfaces.active,
      MemberStatus.inactive => surfaces.inactive,
      MemberStatus.suspended => surfaces.suspended,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        memberStatusLabel(status),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: surfaces.onStatus,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Fixed-height member portrait with authenticated photos and initials fallback.
class MemberPortrait extends StatelessWidget {
  const MemberPortrait({
    super.key,
    required this.member,
    this.badge,
    this.compact = false,
    this.tint,
    this.prominent = false,
  });
  final MemberProfile member;
  final Widget? badge;
  final bool compact;
  final Color? tint;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final brightness = Theme.of(context).brightness;
    if (prominent) {
      return MemberPhotoAvatar.cover(member: member, height: 168);
    }
    return Semantics(
      label: 'Member portrait for ${member.name}',
      child: SizedBox(
        height: compact ? 72 : 100,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? surfaces.panel(AppTone.member, brightness),
          ),
          child: Stack(
            children: [
              Center(
                child: ExcludeSemantics(
                  child: MemberPhotoAvatar(
                    member: member,
                    radius: compact ? 24 : 29,
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Align(alignment: Alignment.topRight, child: badge!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
  });
  final String label;
  final AppTone tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppSurfaces.of(context).accent(tone),
      borderRadius: BorderRadius.circular(AppRadii.control),
      border: Border.all(color: AppSurfaces.of(context).statusBorder(tone)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppSurfaces.of(context).onAccent(tone),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String membershipStatusLabel(Membership membership) =>
    switch (membership.status) {
      'active' =>
        membership.currentlyActive ? 'Active' : 'Active · Not current',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      _ => 'Unavailable',
    };

class MembershipStatusPill extends StatelessWidget {
  const MembershipStatusPill({super.key, required this.membership});
  final Membership membership;
  @override
  Widget build(BuildContext context) => StatusPill(
    label: 'Membership: ${membershipStatusLabel(membership)}',
    tone: membership.currentlyActive
        ? AppTone.positive
        : membership.status == 'expired'
        ? AppTone.expired
        : membership.status == 'active'
        ? AppTone.plan
        : AppTone.warning,
  );
}

/// Dates are saved calendar dates, not UTC instants to shift into device time.
class MembershipCardInfo extends StatelessWidget {
  const MembershipCardInfo({
    super.key,
    required this.membership,
    required this.balancePaise,
    this.available = true,
  });
  final Membership? membership;
  final int? balancePaise;
  final bool available;
  @override
  Widget build(BuildContext context) {
    final plan = membership;
    final dates = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!available)
          const Text('Membership details unavailable')
        else if (plan == null) ...[
          const Text('No membership'),
          const Text('No current membership balance'),
        ] else ...[
          Text(plan.planName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          MembershipStatusPill(membership: plan),
          const SizedBox(height: AppSpacing.sm),
          StatusPill(
            label: balancePaise == null
                ? 'Balance unavailable'
                : balancePaise == 0
                ? 'Fully Paid'
                : '${formatInrPaise(balancePaise!)} Due',
            tone: balancePaise == null
                ? AppTone.neutral
                : balancePaise == 0
                ? AppTone.positive
                : AppTone.payment,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Starts: ${dates.formatShortDate(plan.startDate.value)}'),
          Text(
            'Ends: ${dates.formatShortDate(plan.endDate.value)} (exclusive)',
          ),
        ],
      ],
    );
  }
}

int? currentMembershipBalance(MemberSummary summary) {
  final membership = summary.currentSubscription;
  final money = summary.currentPayments;
  if (membership == null ||
      !membership.currentlyActive ||
      money == null ||
      money.pricePaise != membership.pricePaise ||
      money.paidPaise + money.balancePaise != money.pricePaise) {
    return null;
  }
  return money.balancePaise;
}

/// Only the latest expired history item is shown, explicitly as previous.
/// Cancelled/future records are never substituted for current membership.
Membership? expiredDirectoryMembership(MemberSummary? summary) {
  if (summary == null) return null;
  return _expiredDirectoryMembership(
    summary.history,
    summary.currentSubscription,
  );
}

Membership? _expiredDirectoryMembership(
  List<Membership> history,
  Membership? current,
) {
  if (current != null || history.isEmpty) return null;
  final latest = history.first;
  return latest.status == 'expired' && !latest.currentlyActive ? latest : null;
}

class MemberDirectoryCard extends StatelessWidget {
  const MemberDirectoryCard({
    super.key,
    required this.member,
    required this.onTap,
    this.summary,
    this.memberships,
    this.previousDetails,
    this.outstandingDues,
    this.retry,
  });
  final MemberProfile member;
  final VoidCallback onTap;
  final AsyncValue<MemberSummary?>? summary;
  // The directory uses one complete history for lifecycle and all balances.
  final AsyncValue<List<Membership>?>? memberships;
  final AsyncValue<MembershipDetail?>? previousDetails;

  /// The directory supplies the existing complete, verified membership total.
  /// Standalone cards can still describe a single saved membership.
  final AsyncValue<int?>? outstandingDues;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = summary?.isLoading == false && summary?.hasError == false
        ? summary?.asData?.value
        : null;
    final records =
        memberships?.isLoading == false && memberships?.hasError == false
        ? memberships?.asData?.value
        : null;
    final verified = memberships != null
        ? records != null
        : data != null && data.member.id == member.id;
    final current = memberships != null
        ? records?.where((record) => record.currentlyActive).firstOrNull
        : verified && data?.currentSubscription?.currentlyActive == true
        ? data!.currentSubscription
        : null;
    final previous = records != null
        ? _expiredDirectoryMembership(records, current)
        : verified
        ? expiredDirectoryMembership(data)
        : null;
    final membership = current ?? previous;
    final detail =
        previousDetails?.isLoading == false &&
            previousDetails?.hasError == false
        ? previousDetails?.asData?.value
        : null;
    final oldBalanceVerified =
        previous != null &&
        detail != null &&
        detail.subscription.id == previous.id &&
        detail.subscription.status == 'expired' &&
        !detail.subscription.currentlyActive &&
        detail.subscription.pricePaise == previous.pricePaise &&
        detail.subscription.startDate.value == previous.startDate.value &&
        detail.subscription.endDate.value == previous.endDate.value &&
        detail.payments.paidPaise + detail.payments.balancePaise ==
            previous.pricePaise;
    final savedBalance = memberships != null
        ? null
        : current != null
        ? currentMembershipBalance(data!)
        : oldBalanceVerified
        ? detail.payments.balancePaise
        : null;
    final balance = outstandingDues == null
        ? savedBalance
        : outstandingDues!.isLoading || outstandingDues!.hasError
        ? null
        : outstandingDues!.asData?.value;
    final tone = previous != null
        ? MemberCardTone.expired
        : current != null && balance == 0
        ? MemberCardTone.paid
        : current != null && balance != null && balance > 0
        ? MemberCardTone.due
        : MemberCardTone.neutral;
    final color = AppSurfaces.of(context).memberCard(tone, theme.brightness);
    final amountStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );
    final dueAmount = balance != null && balance > 0
        ? Text(
            '${formatInrPaise(balance)} due',
            style: amountStyle?.copyWith(
              color: PendingColors.accentFor(theme.brightness),
            ),
          )
        : null;
    final status = !verified || membership == null
        ? null
        : previous != null
        ? Semantics(
            label: 'Expired previous membership. No current membership.',
            child: const ExcludeSemantics(
              child: StatusPill(label: 'Expired', tone: AppTone.expired),
            ),
          )
        : balance == 0
        ? const StatusPill(label: 'Fully Paid', tone: AppTone.positive)
        : null;
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(member.name, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        // Complete dues come from verified balances across every history page.
        if (dueAmount != null) ...[
          dueAmount,
          const SizedBox(height: AppSpacing.sm),
        ],
        if ((memberships ?? summary)?.isLoading == true) ...[
          const LinearProgressIndicator(),
          const Text('Loading membership…'),
        ] else if (!verified) ...[
          const Text('Membership details unavailable'),
          if (retry != null)
            TextButton(onPressed: retry, child: const Text('Retry membership')),
        ] else if (membership == null)
          const StatusPill(label: 'No membership')
        else ...[
          if (dueAmount == null && (balance == null || previous != null)) ...[
            if (balance == 0)
              Text('No balance due', style: amountStyle)
            else
              const StatusPill(label: 'Balance unavailable'),
            const SizedBox(height: AppSpacing.sm),
          ],
          MembershipDateRange(
            start: membership.startDate.value,
            end: membership.endDate.value,
            previous: previous != null,
            singleLine: true,
          ),
          if (previousDetails?.isLoading == true)
            const LinearProgressIndicator()
          else if (previousDetails?.hasError == true && retry != null)
            TextButton(onPressed: retry, child: const Text('Retry balance')),
          if (outstandingDues?.isLoading == true)
            const Text('Checking all balances…')
          else if (outstandingDues?.hasError == true && retry != null)
            TextButton(onPressed: retry, child: const Text('Retry balance')),
        ],
      ],
    );
    return Semantics(
      button: true,
      label: 'View profile for ${member.name}',
      child: Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  MemberPortrait(member: member, prominent: true),
                  if (current != null)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Semantics(
                        container: true,
                        label: 'Active membership',
                        child: Tooltip(
                          message: 'Active membership',
                          excludeFromSemantics: true,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppSurfaces.of(
                                context,
                              ).onAccent(AppTone.positive),
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (status != null)
                    Positioned(
                      bottom: AppSpacing.sm,
                      left: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: status,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: footer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Natural card heights keep long names/dates readable instead of clipping into
/// a fixed grid aspect ratio. Normal phones use two columns; large text uses one.
class ResponsiveMemberGrid extends StatelessWidget {
  const ResponsiveMemberGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 328 &&
              MediaQuery.textScalerOf(context).scale(14) / 14 <= 1.25
          ? 2
          : 1;

      return Column(
        children: [
          for (var index = 0; index < children.length; index += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: columns == 1
                  ? children[index]
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: children[index]),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: index + 1 < children.length
                                ? children[index + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
            ),
        ],
      );
    },
  );
}

class MembersFeedbackPanel extends StatelessWidget {
  const MembersFeedbackPanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.loading = false,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => SoftPanel(
    child: Column(
      children: [
        if (loading)
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              semanticsLabel: 'Loading members',
            ),
          )
        else
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );
}
