import 'package:flutter/material.dart';
import '../../../shared/contact/member_contact.dart';
import '../../members/birthdays.dart';
import '../../leads/lead_widgets.dart';
import '../../leads/leads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/glass.dart';
import '../../gym_settings/gym_settings.dart';
import '../../members/models/member_overview.dart';
import '../../members/presentation/member_overview_widgets.dart';
import '../../members/providers/member_overview_providers.dart';
import '../../memberships/providers/plan_providers.dart';
import '../../owner_profile/owner_profile.dart';
import '../models/dashboard_models.dart';
import '../providers/dashboard_providers.dart';
import '../../../shared/widgets/page_section.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String greetingFor(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

/// Opens the Members tab with a filter already applied.
void openMembersFiltered(
  BuildContext context,
  WidgetRef ref,
  MemberOverviewFilter filter,
) {
  ref.read(memberOverviewQueryProvider.notifier).select(filter);
  context.go(AppRoutes.members);
}

/// "Saturday, 14 Nov" over "Good afternoon, Raj".
class DashboardGreeting extends ConsumerWidget {
  const DashboardGreeting({super.key, this.now});

  /// Test seam; defaults to the phone clock.
  final DateTime? now;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = currentOwnerProfile(ref);
    final time = now ?? DateTime.now();
    final firstName = profile?.name.trim().split(RegExp(r'\s+')).first ?? '';
    final date =
        '${_weekdays[time.weekday - 1]}, ${time.day} ${_months[time.month - 1]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // The shell header already shows the gym name.
          date,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          firstName.isEmpty
              ? greetingFor(time)
              : '${greetingFor(time)}, $firstName',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A setup step for new owners. Done steps are ticked; the list hides when complete.
class SetupStep {
  const SetupStep(this.label, this.done, this.actionLabel, this.onTap);
  final String label;
  final bool done;
  final String actionLabel;
  final VoidCallback onTap;
}

List<SetupStep> setupSteps({
  required BuildContext context,
  required AdminGymContext gym,
  required GymSettings? settings,
  required int? planCount,
  required GymDashboard? dashboard,
}) => [
  SetupStep(
    'Set your gym’s timezone',
    settings?.timezoneConfigured ?? true,
    'Set',
    () => context.push(AppRoutes.gymSettings),
  ),
  SetupStep(
    'Create a membership plan',
    (planCount ?? 1) > 0,
    'Create',
    () => context.push(
      '${AppRoutes.plans}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
    ),
  ),
  SetupStep(
    'Add your first member',
    (dashboard?.members.total ?? 1) > 0,
    'Add',
    () => context.push(
      '${AppRoutes.members}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
    ),
  ),
  SetupStep(
    'Add a trainer',
    (dashboard?.trainers.total ?? 1) > 0,
    'Add',
    () => context.push(
      '${AppRoutes.trainers}/new?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
    ),
  ),
  SetupStep(
    'Add your GST number and address',
    settings == null || (settings.gstin != null && settings.address != null),
    'Add',
    () => context.push(AppRoutes.gymSettings),
  ),
];

class SetupChecklist extends ConsumerWidget {
  const SetupChecklist({super.key, required this.gym, required this.dashboard});
  final AdminGymContext gym;
  final GymDashboard? dashboard;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(gymSettingsProvider).asData?.value;
    final plans = ref.watch(activePlanCountProvider).asData?.value;
    // Wait for real data: never show a half-known checklist.
    if (settings == null || plans == null || dashboard == null) {
      return const SizedBox.shrink();
    }
    final steps = setupSteps(
      context: context,
      gym: gym,
      settings: settings,
      planCount: plans,
      dashboard: dashboard,
    );
    final done = steps.where((step) => step.done).length;
    if (done == steps.length) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Finish setting up',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$done of ${steps.length} done',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / steps.length,
                minHeight: 4,
                backgroundColor: AppPalette.graphite,
                semanticsLabel: 'Setup progress',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      step.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: step.done
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        step.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: step.done
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                          decoration: step.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (!step.done)
                      TextButton(
                        onPressed: step.onTap,
                        child: Text(step.actionLabel),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Today's to-do: memberships ending soon, money to collect, and lapsed members.
class DashboardTodo extends ConsumerWidget {
  const DashboardTodo({super.key, required this.gym});
  final AdminGymContext gym;

  static const sections = [
    (
      filter: MemberOverviewFilter.expiring,
      title: 'Expiring in 7 days',
      icon: Icons.hourglass_bottom_rounded,
      empty: 'No memberships end this week.',
    ),
    (
      filter: MemberOverviewFilter.dues,
      title: 'Dues to collect',
      icon: Icons.payments_outlined,
      empty: 'Nobody owes money right now.',
    ),
    (
      filter: MemberOverviewFilter.expired,
      title: 'Expired, not renewed',
      icon: Icons.person_off_outlined,
      empty: 'Every expired member has renewed.',
    ),
    (
      filter: MemberOverviewFilter.inactive,
      title: 'Not visited in 10+ days',
      icon: Icons.directions_walk_outlined,
      empty: 'Every active member visited recently.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gymName = currentOwnerProfile(ref)?.gymName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Today’s to-do', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Members who need a call, a reminder or a renewal.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FollowUpSection(),
        for (final section in sections)
          _TodoSection(
            gym: gym,
            gymName: gymName,
            filter: section.filter,
            title: section.title,
            icon: section.icon,
            empty: section.empty,
          ),
        _BirthdaySection(gymName: gymName),
      ],
    );
  }
}

/// Enquiries whose follow-up is today or overdue.
class _FollowUpSection extends ConsumerWidget {
  const _FollowUpSection();
  static const _query = (filter: LeadFilter.due, search: '', page: 1);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(leadsProvider(_query));
    final page = state.asData?.value;
    final total = page?.pagination.total;
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole header opens Enquiries: a separate button does not fit
          // narrow phones with large text.
          Semantics(
            button: true,
            label: 'Open enquiries to follow up',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              onTap: () {
                ref.read(leadQueryProvider.notifier).select(LeadFilter.due);
                context.push(AppRoutes.leads);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(
                      Icons.contact_phone_outlined,
                      size: 20,
                      color: AppPalette.amber,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        total == null
                            ? 'Enquiry follow-ups'
                            : 'Enquiry follow-ups · $total',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppPalette.amber,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.isLoading && page == null)
            const LinearProgressIndicator(minHeight: 2)
          else if (state.hasError)
            const Text('Couldn’t load enquiries.')
          else if (page != null && page.leads.isEmpty)
            Text(
              'No enquiries to follow up today.',
              style: theme.textTheme.bodySmall,
            )
          else if (page != null)
            for (final lead in page.leads.take(3)) ...[
              LeadTile(lead: lead, compact: true),
              if (lead != page.leads.take(3).last)
                const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

/// Members with a birthday in the next 7 days, with a WhatsApp wish.
class _BirthdaySection extends ConsumerWidget {
  const _BirthdaySection({required this.gymName});
  final String gymName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final birthdays = ref.watch(upcomingBirthdaysProvider).asData?.value;
    if (birthdays == null || birthdays.isEmpty) return const SizedBox.shrink();
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.cake_outlined, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text('Birthdays this week', style: theme.textTheme.titleSmall),
            ],
          ),
          for (final birthday in birthdays.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(birthday.member.name),
              subtitle: Text(birthday.whenLabel),
              trailing: IconButton(
                tooltip: 'Wish ${birthday.member.firstName} on WhatsApp',
                onPressed: () => whatsappMember(
                  context,
                  birthday.member.phone,
                  ReminderMessages.birthday(
                    firstName: birthday.member.firstName,
                    today: birthday.daysUntil == 0,
                    gymName: gymName,
                  ),
                ),
                icon: const Icon(Icons.chat_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodoSection extends ConsumerWidget {
  const _TodoSection({
    required this.gym,
    required this.gymName,
    required this.filter,
    required this.title,
    required this.icon,
    required this.empty,
  });
  final AdminGymContext gym;
  final String gymName;
  final MemberOverviewFilter filter;
  final String title, empty;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(
      memberOverviewProvider(MemberOverviewQuery(filter: filter, limit: 3)),
    );
    final page = state.asData?.value;
    final total = page?.pagination.total;
    final color = switch (filter) {
      MemberOverviewFilter.expiring => AppPalette.amber,
      MemberOverviewFilter.dues => AppPalette.accentLight,
      MemberOverviewFilter.inactive => AppPalette.amber,
      _ => theme.colorScheme.onSurface,
    };
    final heading = filter == MemberOverviewFilter.dues && page != null
        ? '$title · ${formatCompactInrPaise(page.duesTotalPaise)}'
        : total == null
        ? title
        : '$title · $total';
    return PlainBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  heading,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
              if ((total ?? 0) > 0)
                TextButton(
                  onPressed: () => openMembersFiltered(context, ref, filter),
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.isLoading && page == null)
            const LinearProgressIndicator(minHeight: 2)
          else if (state.hasError)
            Row(
              children: [
                const Expanded(child: Text('Couldn’t load this list.')),
                TextButton(
                  onPressed: () => ref.invalidate(memberOverviewProvider),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (page != null && page.rows.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(empty, style: theme.textTheme.bodySmall)),
              ],
            )
          else if (page != null)
            for (final row in page.rows) ...[
              MemberOverviewTile(
                row: row,
                gym: gym,
                gymName: gymName,
                compact: true,
                showVisits: filter == MemberOverviewFilter.inactive,
              ),
              if (row != page.rows.last) const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}
