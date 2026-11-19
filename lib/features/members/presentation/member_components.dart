import '../../../shared/widgets/membership_date_range.dart';
import 'member_list_widgets.dart';
import '../../../shared/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/feedback_notice.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../data/member_failure.dart';
import '../providers/member_providers.dart';
import '../models/member_models.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/profile_section.dart';
export '../../../shared/widgets/page_controls.dart';

String memberPath(MemberScope scope, {bool edit = false}) =>
    '${AppRoutes.members}/${scope.memberId}${edit ? '/edit' : ''}?gymId=${Uri.encodeQueryComponent(scope.gymId)}';

class MemberError extends StatelessWidget {
  const MemberError({super.key, required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => FeedbackNotice(
    message: error is MemberFailure
        ? (error as MemberFailure).message
        : 'Member information could not be loaded. Please try again.',
    retry: retry,
    primaryRetry: true,
  );
}

class MemberContextChanged extends StatelessWidget {
  const MemberContextChanged({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('The gym context changed. Return to Members to continue.'),
          TextButton(
            onPressed: () => context.go(AppRoutes.members),
            child: const Text('Return to Members'),
          ),
        ],
      ),
    ),
  );
}

typedef MemberSection = ProfileSection;

Widget membershipText(Membership membership) => Builder(
  builder: (context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(membership.planName, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      IconLabel(
        'Saved plan price: ${formatInrPaise(membership.pricePaise)} · ${membership.durationDays} days',
        style: Theme.of(context).textTheme.titleMedium,
        icon: Icons.sell_outlined,
      ),
      const SizedBox(height: 8),
      MembershipDateRange(
        start: membership.startDate.value,
        end: membership.endDate.value,
      ),
      Text(
        'End date exclusive · gym timezone',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      MembershipStatusPill(membership: membership),
    ],
  ),
);
