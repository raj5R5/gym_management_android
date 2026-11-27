import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/contact/member_contact.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/page_section.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../memberships/presentation/billing_components.dart';
import '../models/member_overview.dart';
import '../photos/member_photo_widgets.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import '../../../shared/widgets/card_reveal.dart';

/// Status colour for a row: red for money or lapsed access, amber for soon.
Color overviewStatusColor(BuildContext context, MemberOverviewRow row) {
  final membership = row.membership;
  if (membership == null) return Theme.of(context).colorScheme.onSurfaceVariant;
  if (membership.state == OverviewMembershipState.expired) {
    return AppPalette.accentLight;
  }
  if (membership.expiringSoon) return AppPalette.amber;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// The WhatsApp draft that fits this member's situation.
String overviewReminder(
  MemberOverviewRow row,
  String gymName, {
  bool missedVisits = false,
}) {
  if (missedVisits && row.membership?.state == OverviewMembershipState.active) {
    return ReminderMessages.missYou(
      firstName: row.member.firstName,
      gymName: gymName,
    );
  }
  final membership = row.membership;
  final name = row.member.firstName;
  if (row.balancePaise > 0 &&
      (membership == null || !membership.expiringSoon)) {
    return ReminderMessages.dues(
      firstName: name,
      balancePaise: row.balancePaise,
      gymName: gymName,
    );
  }
  if (membership?.state == OverviewMembershipState.expired) {
    return ReminderMessages.expired(
      firstName: name,
      planName: membership!.planName,
      gymName: gymName,
    );
  }
  if (membership != null && membership.expiringSoon) {
    return ReminderMessages.expiring(
      firstName: name,
      planName: membership.planName,
      daysLeft: membership.daysLeft,
      gymName: gymName,
    );
  }
  return 'Hi $name,';
}

enum OverviewAction { collect, renew, addPlan, none }

OverviewAction overviewActionFor(MemberOverviewRow row) {
  if (row.balancePaise > 0) return OverviewAction.collect;
  final membership = row.membership;
  if (membership == null) return OverviewAction.addPlan;
  if (membership.state == OverviewMembershipState.expired ||
      membership.expiringSoon) {
    return OverviewAction.renew;
  }
  return OverviewAction.none;
}

/// Opens the screen where the owner records a payment or renews.
void openOverviewAction(
  BuildContext context,
  AdminGymContext gym,
  MemberOverviewRow row,
) {
  final scope = scopeFor(gym, row.member.id);
  switch (overviewActionFor(row)) {
    case OverviewAction.collect:
      context.push(
        membershipPath(scope, subscriptionId: row.dueSubscriptionId),
      );
    case OverviewAction.renew || OverviewAction.addPlan:
      context.push(membershipPath(scope));
    case OverviewAction.none:
      context.push(memberPath(scope));
  }
}

/// Compact member row: who, which plan, how long is left, and one next step.
class MemberOverviewTile extends StatelessWidget {
  const MemberOverviewTile({
    super.key,
    required this.row,
    required this.gym,
    required this.gymName,
    this.compact = false,
    this.showVisits = false,
  });
  final MemberOverviewRow row;
  final AdminGymContext gym;
  final String gymName;

  /// Lists about attendance: show the last visit and use the "we miss you" draft.
  final bool showVisits;

  /// Dashboard lists: one line of detail, no progress bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membership = row.membership;
    final statusColor = overviewStatusColor(context, row);
    final action = overviewActionFor(row);
    final detail = showVisits
        ? row.lastVisitLabel
        : membership == null
        ? 'No membership yet'
        : '${membership.planName} · ${membership.statusLabel}';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                row.member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                row.member.memberCode,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
        ),
        if (!compact &&
            membership != null &&
            membership.state == OverviewMembershipState.active) ...[
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: membership.usedFraction,
                minHeight: 3,
                color: membership.expiringSoon
                    ? AppPalette.amber
                    : theme.colorScheme.primary,
                backgroundColor: AppPalette.graphite,
              ),
            ),
          ),
        ],
      ],
    );
    final contact = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIcon(
          tooltip: 'Call ${row.member.firstName}',
          icon: Icons.call_outlined,
          onPressed: () => callMember(context, row.member.phone),
        ),
        const SizedBox(width: AppSpacing.xs),
        _RoundIcon(
          tooltip: 'WhatsApp ${row.member.firstName}',
          icon: Icons.chat_outlined,
          onPressed: () => whatsappMember(
            context,
            row.member.phone,
            overviewReminder(row, gymName, missedVisits: showVisits),
          ),
        ),
      ],
    );
    final next = _ActionPill(row: row, action: action, gym: gym);
    // Large text or a narrow screen: the actions go under the details.
    final stacked =
        MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3 ||
        MediaQuery.sizeOf(context).width < 340;
    return Semantics(
      container: true,
      label:
          '${row.member.name}, $detail'
          '${row.balancePaise > 0 ? ', ${formatCompactInrPaise(row.balancePaise)} due' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () =>
            pushFromCard(context, memberPath(scopeFor(gym, row.member.id))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: MemberPhotoAvatar(
                  member: row.member,
                  radius: compact ? 18 : 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [next, contact],
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: info),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              next,
                              const SizedBox(height: AppSpacing.xs),
                              contact,
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Members as rows with a thin line between them, not a card each.
class MemberOverviewList extends StatelessWidget {
  const MemberOverviewList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      SeparatedRows(indent: 56, children: children);
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.cardBorder),
      minimumSize: const Size(40, 40),
    ),
    icon: Icon(icon),
  );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.row,
    required this.action,
    required this.gym,
  });
  final MemberOverviewRow row;
  final OverviewAction action;
  final AdminGymContext gym;
  @override
  Widget build(BuildContext context) {
    final label = switch (action) {
      OverviewAction.collect =>
        'Collect ${formatCompactInrPaise(row.balancePaise)}',
      OverviewAction.renew => 'Renew',
      OverviewAction.addPlan => 'Add plan',
      OverviewAction.none => 'Paid in full',
    };
    if (action == OverviewAction.none) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      );
    }
    final danger = action == OverviewAction.collect;
    return OutlinedButton(
      onPressed: () => openOverviewAction(context, gym, row),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        foregroundColor: danger ? AppPalette.accentLight : null,
        side: BorderSide(
          color: danger
              ? AppPalette.accentLight.withValues(alpha: .6)
              : AppColors.cardBorder,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Filter chips with live counts, e.g. "Expiring 3".
class OverviewFilterChips extends StatelessWidget {
  const OverviewFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
    this.counts,
  });
  final MemberOverviewFilter selected;
  final ValueChanged<MemberOverviewFilter> onSelected;
  final MemberOverviewCounts? counts;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final filter in MemberOverviewFilter.values) ...[
          ChoiceChip(
            label: Text(
              counts == null
                  ? filter.label
                  : '${filter.label} ${counts![filter]}',
            ),
            selected: filter == selected,
            onSelected: (_) => onSelected(filter),
            labelStyle: TextStyle(
              // Selected chips are filled pearl; their label must be dark.
              color: filter == selected
                  ? AppPalette.onAccent
                  : switch (filter) {
                      MemberOverviewFilter.expiring => AppPalette.amber,
                      MemberOverviewFilter.dues ||
                      MemberOverviewFilter.expired => AppPalette.accentLight,
                      MemberOverviewFilter.inactive => AppPalette.amber,
                      _ => null,
                    },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ],
    ),
  );
}
