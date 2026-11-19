import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/photos/member_photo_widgets.dart';
import '../members/presentation/member_components.dart';
import '../members/providers/member_providers.dart';
import 'visit_models.dart';
import 'visit_repository.dart';
import '../../shared/widgets/page_section.dart';
import '../../shared/widgets/card_reveal.dart';

class TodayVisitsPage extends ConsumerWidget {
  const TodayVisitsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(todayVisitsProvider);
    final gym = ref.watch(adminGymProvider);
    final data = state.asData?.value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayVisitsProvider);
        try {
          await ref.read(todayVisitsProvider.future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Today’s check-ins', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          if (data != null)
            Text(
              data.overrides == 0
                  ? '${data.total} ${data.total == 1 ? 'visit' : 'visits'}'
                  : '${data.total} visits · ${data.overrides} without an active membership',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (state.hasError)
            Column(
              children: [
                Text(
                  state.error is VisitFailure
                      ? (state.error! as VisitFailure).message
                      : 'Check-ins could not be loaded.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(todayVisitsProvider),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (data != null && data.rows.isEmpty)
            const PlainBlock(
              child: Text(
                'Nobody has checked in yet today. Scan a member QR or search a member to check them in.',
              ),
            )
          else if (data != null && gym != null)
            SeparatedRows(
              indent: 56,
              children: [
                for (final row in data.rows)
                  Builder(
                    builder: (tileContext) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => pushFromCard(
                        tileContext,
                        memberPath(scopeFor(gym, row.member.id)),
                      ),
                      leading: ExcludeSemantics(
                        child: MemberPhotoAvatar(
                          member: row.member,
                          radius: 20,
                        ),
                      ),
                      title: Text(row.member.name),
                      subtitle: Text(
                        [
                          row.member.memberCode,
                          if (row.visit.method == VisitMethod.qr) 'QR',
                          if (row.visit.override) 'No active membership',
                        ].join(' · '),
                        style: row.visit.override
                            ? const TextStyle(color: AppPalette.amber)
                            : null,
                      ),
                      trailing: Text(
                        TimeOfDay.fromDateTime(
                          row.visit.checkedInAt,
                        ).format(context),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
