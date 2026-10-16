import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/formatting/payment_date.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../memberships/models/billing_models.dart';
import '../models/member_models.dart';
import '../providers/member_providers.dart';
import 'member_components.dart';
import 'member_list_widgets.dart';
import '../photos/member_photo_widgets.dart';

class MemberProfileCard extends StatelessWidget {
  const MemberProfileCard({
    super.key,
    required this.member,
    required this.scope,
  });
  final MemberProfile member;
  final MemberScope scope;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            member.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Member code: ${member.memberCode}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: 'Member status',
          child: MemberStatusBadge(status: member.status),
        ),
      ],
    );
    final portrait = MemberPhotoAvatar.cover(
      member: member,
      width: 128,
      height: 128,
      borderRadius: BorderRadius.circular(AppRadii.control),
      viewable: true,
    );
    final edit = OutlinedButton.icon(
      onPressed: () => context.push(memberPath(scope, edit: true)),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('Edit member'),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SoftPanel(
        tone: AppTone.neutral,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('MEMBER PROFILE', style: theme.textTheme.labelSmall),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 288 ||
                    MediaQuery.textScalerOf(context).scale(14) / 14 > 1.4) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      portrait,
                      const SizedBox(height: AppSpacing.md),
                      identity,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    portrait,
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: identity),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerLeft, child: edit),
            const Divider(height: AppSpacing.xl),
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
                    .map(
                      (part) => '${part[0].toUpperCase()}${part.substring(1)}',
                    )
                    .join(' '),
              ),
            if (member.address?.display.isNotEmpty == true)
              MemberInfoLine(
                icon: Icons.location_on_outlined,
                label: 'Address',
                value: member.address!.display,
              ),
          ],
        ),
      ),
    );
  }
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
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppSurfaces.of(
                context,
              ).panel(AppTone.neutral, Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
  });
  final int? paidPaise, balancePaise;
  final String paidLabel, dueLabel;
  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int? amount, AppTone tone) => SoftPanel(
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
  });
  final Membership membership;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final name = Text(
            membership.planName,
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
          );
          final status = Semantics(
            label: 'Membership status',
            child: MembershipStatusPill(membership: membership),
          );
          if (constraints.maxWidth < 300 ||
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
      MembershipDateRange(
        start: membership.startDate.value,
        end: membership.endDate.value,
      ),
      if (compact)
        Text(
          '${membership.durationDays} days · ${formatInrPaise(membership.pricePaise)} · UTC calendar',
          style: Theme.of(context).textTheme.bodySmall,
        )
      else ...[
        Text(
          'Membership dates · UTC calendar',
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
  Widget build(BuildContext context) => Column(
    children: [
      if (summary.member.emergencyContact case final EmergencyContact contact)
        ProfileSection(
          title: 'Emergency contact',
          icon: Icons.contact_phone_outlined,
          tone: AppTone.member,
          children: [
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
        ),
      ProfileSection(
        title: 'Gym & trainers',
        icon: Icons.fitness_center_outlined,
        tone: AppTone.plan,
        children: [
          MemberInfoLine(
            icon: Icons.storefront_outlined,
            label: 'Branch',
            value: summary.branch == null
                ? 'No current branch available'
                : '${summary.branch!.name} (${summary.branch!.status})',
          ),
          if (summary.trainers.isEmpty) const Text('No assigned trainers.'),
          for (final trainer in summary.trainers)
            MemberInfoLine(
              icon: Icons.fitness_center,
              label: 'Assigned trainer · ${trainer.code}',
              value: '${trainer.name}\n${trainer.phone}',
            ),
        ],
      ),
    ],
  );
}

class MemberLatestPayment extends StatelessWidget {
  const MemberLatestPayment({super.key, required this.payments});
  final MemberPaymentSummary payments;
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
    return MemberInfoLine(
      icon: Icons.check_circle_outline,
      label: 'Latest successful payment',
      value:
          '${formatInrPaise(latest.amountPaise)} · $method\n${formatPaymentDateTime(MaterialLocalizations.of(context), latest.paidAt, timezone: 'UTC')}',
    );
  }
}
