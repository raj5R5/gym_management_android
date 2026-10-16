import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/membership_date_range.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../models/membership_eligibility.dart';
import 'billing_components.dart';

class MembershipEligibilityNotice extends StatelessWidget {
  const MembershipEligibilityNotice({
    super.key,
    required this.membership,
    required this.scope,
    required this.retry,
    this.onView,
  });
  final Membership membership;
  final MemberScope scope;
  final VoidCallback retry;
  final VoidCallback? onView;
  @override
  Widget build(BuildContext context) => ProfileSection(
    title: 'Membership already available',
    tone: AppTone.plan,
    children: [
      const Text(activeMembershipMessage),
      Text(membership.planName, style: Theme.of(context).textTheme.titleMedium),
      MembershipDateRange(
        start: membership.startDate.value,
        end: membership.endDate.value,
      ),
      const Text('Eligible once the end date above is reached (UTC).'),
      FilledButton.icon(
        onPressed:
            onView ??
            () => context.push(
              membershipPath(scope, subscriptionId: membership.id),
            ),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('View existing membership & payments'),
      ),
      TextButton(onPressed: retry, child: const Text('Recheck eligibility')),
    ],
  );
}
