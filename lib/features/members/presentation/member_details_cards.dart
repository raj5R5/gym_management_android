import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/contact/member_contact.dart';
import '../../../shared/formatting/payment_date.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../../shared/widgets/round_action.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../memberships/models/billing_models.dart';
import '../../memberships/presentation/plan_duration_summary.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import 'member_list_widgets.dart';
import '../photos/member_photo_widgets.dart';
import '../../visits/member_visit_widgets.dart';

/// Who the member is and how to reach them, at a glance: photo, name,
/// code and status, then one row of quick actions.
class MemberProfileCard extends ConsumerWidget {
  const MemberProfileCard({
    super.key,
    required this.member,
    required this.scope,
  });
  final MemberProfile member;
  final MemberScope scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 72,
                child: MemberPhotoAvatar.cover(
                  member: member,
                  width: 72,
                  height: 72,
                  borderRadius: BorderRadius.circular(36),
                  viewable: true,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        member.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Semantics(
                      label: 'Member profile status',
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Member code: ${member.memberCode}',
                            style: theme.textTheme.bodySmall,
                          ),
                          MemberStatusBadge(status: member.status),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          RoundActionRow(
            actions: [
              RoundAction(
                icon: Icons.call_outlined,
                label: 'Call',
                onTap: () => callMember(context, member.phone),
              ),
              RoundAction(
                icon: Icons.chat_outlined,
                label: 'WhatsApp',
                onTap: () => whatsappMember(
                  context,
                  member.phone,
                  'Hi ${member.firstName},',
                ),
              ),
              RoundAction(
                icon: Icons.login,
                label: 'Check in',
                onTap: () => checkInMember(context, ref, member),
              ),
              RoundAction(
                icon: Icons.edit_outlined,
                label: 'Edit member',
                onTap: () => context.push(memberPath(scope, edit: true)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Secondary information stays available without competing with membership/dues.
class MemberDetailsDisclosure extends StatelessWidget {
  const MemberDetailsDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Matches the icon column of the activity rows above.
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: PageStorageKey(title),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.lg),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: icon == null ? null : Icon(icon),
        title: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        children: children,
      ),
    ),
  );
}

class MemberPersonalDetails extends StatelessWidget {
  const MemberPersonalDetails({super.key, required this.member});
  final MemberProfile member;
  @override
  Widget build(BuildContext context) => MemberDetailsDisclosure(
    title: 'Contact & personal details',
    subtitle: member.phone,
    icon: Icons.contact_phone_outlined,
    children: [
      MemberInfoLine(
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: member.phone,
      ),
      if (member.dateOfBirth != null)
        MemberInfoLine(
          icon: Icons.cake_outlined,
          label: 'Date of birth',
          value: MaterialLocalizations.of(
            context,
          ).formatShortDate(member.dateOfBirth!.value),
        ),
      if (member.gender?.trim().isNotEmpty == true)
        MemberInfoLine(
          icon: Icons.person_outline,
          label: 'Gender',
          value: member.gender!
              .split('_')
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' '),
        ),
      if (member.address?.display.isNotEmpty == true)
        MemberInfoLine(
          icon: Icons.location_on_outlined,
          label: 'Address',
          value: member.address!.display,
        ),
      if (member.emergencyContact case final EmergencyContact contact) ...[
        const Divider(height: AppSpacing.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            header: true,
            child: Text(
              'Emergency contact',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        MemberInfoLine(
          icon: Icons.contact_phone_outlined,
          label: contact.relationship ?? 'Contact',
          value: contact.name,
        ),
        MemberInfoLine(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: contact.phone,
        ),
      ],
    ],
  );
}

class MemberInfoLine extends StatelessWidget {
  const MemberInfoLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Labeled values share one responsive layout without clipping large INR values.
class MemberAmounts extends StatelessWidget {
  const MemberAmounts({
    super.key,
    required this.paidPaise,
    required this.balancePaise,
    this.paidLabel = 'Amount paid',
    this.dueLabel = 'Outstanding balance',
    this.compact = false,
  });
  final int? paidPaise, balancePaise;
  final String paidLabel, dueLabel;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int? amount, AppTone tone) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            amount == null ? 'Unavailable' : formatInrPaise(amount),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: amount != null && tone == AppTone.pending
                  ? PendingColors.accentFor(Theme.of(context).brightness)
                  : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
      if (compact) return content;
      return SoftPanel(
        tone: tone,
        backgroundColor: tone == AppTone.pending
            ? PendingColors.surfaceFor(Theme.of(context).brightness)
            : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              amount == null ? 'Unavailable' : formatInrPaise(amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: amount != null && tone == AppTone.pending
                    ? PendingColors.accentFor(Theme.of(context).brightness)
                    : null,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    final paid = tile(paidLabel, paidPaise, AppTone.positive);
    final due = tile(
      dueLabel,
      balancePaise,
      balancePaise == null
          ? AppTone.neutral
          : balancePaise == 0
          ? AppTone.positive
          : AppTone.pending,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              paid,
              const SizedBox(height: AppSpacing.sm),
              due,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: paid),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: due),
          ],
        );
      },
    );
  }
}

class SavedMembershipSummary extends StatelessWidget {
  const SavedMembershipSummary({
    super.key,
    required this.membership,
    this.compact = false,
    this.emphasizeDuration = false,
  });
  final Membership membership;
  final bool compact;
  final bool emphasizeDuration;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final nameText = Text(
            membership.planName,
            style: compact && !emphasizeDuration
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
          );
          final name = emphasizeDuration
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlanDurationInfoButton(
                      planName: membership.planName,
                      durationDays: membership.durationDays,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: nameText),
                  ],
                )
              : nameText;
          final status = Semantics(
            label: 'Membership status',
            child: MembershipStatusPill(membership: membership),
          );
          if (constraints.maxWidth < (emphasizeDuration ? 360 : 300) ||
              MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: AppSpacing.sm),
                status,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: name),
              const SizedBox(width: AppSpacing.md),
              status,
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.md),
      if (emphasizeDuration) ...[
        PlanDurationSummary(durationDays: membership.durationDays),
        const SizedBox(height: AppSpacing.lg),
      ],
      MembershipDateRange(
        start: membership.startDate.value,
        end: membership.endDate.value,
      ),
      if (emphasizeDuration) ...[
        Text(
          [
            'Membership dates · gym timezone',
            if (membership.frozenDays > 0)
              'includes ${membership.frozenDays} frozen ${membership.frozenDays == 1 ? 'day' : 'days'}',
            if (membership.discountPaise > 0)
              '${formatCompactInrPaise(membership.discountPaise)} discount given',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Saved plan price: ${formatInrPaise(membership.pricePaise)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ] else if (compact)
        Text(
          '${membership.durationDays} days · ${formatInrPaise(membership.pricePaise)} · gym timezone',
          style: Theme.of(context).textTheme.bodySmall,
        )
      else ...[
        Text(
          'Membership dates · gym timezone',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Plan price: ${formatInrPaise(membership.pricePaise)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${membership.durationDays} days · Saved plan price',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}

class MemberSupportCards extends StatelessWidget {
  const MemberSupportCards({super.key, required this.summary});
  final MemberSummary summary;
  @override
  Widget build(BuildContext context) => MemberDetailsDisclosure(
    title: 'Assigned trainers',
    icon: Icons.fitness_center_outlined,
    children: [
      if (summary.trainers.isEmpty)
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('No assigned trainers.'),
        ),
      for (final trainer in summary.trainers)
        MemberInfoLine(
          icon: Icons.fitness_center_outlined,
          label: 'Assigned trainer · ${trainer.code}',
          value: '${trainer.name}\n${trainer.phone}',
        ),
    ],
  );
}

class MemberLatestPayment extends StatelessWidget {
  const MemberLatestPayment({
    super.key,
    required this.payments,
    this.timezone,
    this.compact = false,
  });
  final MemberPaymentSummary payments;
  final String? timezone;

  /// One short line, for a list row.
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final latest = payments.latest;
    if (latest == null) {
      return Text(
        payments.count == 0
            ? 'No successful payments.'
            : 'Latest payment details unavailable. Open payment history.',
      );
    }
    final method =
        PaymentMethod.values
            .where((method) => method.wireValue == latest.method)
            .firstOrNull
            ?.label ??
        'Method unavailable';
    if (compact) {
      return Text(
        'Last ${formatInrPaise(latest.amountPaise)} · $method · '
        '${formatPaymentDateTime(MaterialLocalizations.of(context), latest.paidAt, timezone: timezone, showZone: false)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return MemberInfoLine(
      icon: Icons.check_circle_outline,
      label: 'Latest successful payment',
      value:
          '${formatInrPaise(latest.amountPaise)} · $method\n${formatPaymentDateTime(MaterialLocalizations.of(context), latest.paidAt, timezone: timezone)}',
    );
  }
}
