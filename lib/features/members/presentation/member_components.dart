import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            error is MemberFailure
                ? (error as MemberFailure).message
                : 'Member information could not be loaded. Please try again.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
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

Widget membershipText(Membership membership) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(membership.planName),
    Text(
      'Plan snapshot: ${membership.durationDays} days · ${formatInrPaise(membership.pricePaise)}',
    ),
    Text('${membership.startDate} to ${membership.endDate} (end exclusive)'),
    Text(
      'Status: ${membership.status} · ${membership.currentlyActive ? 'Current' : 'Not current'}',
    ),
  ],
);
