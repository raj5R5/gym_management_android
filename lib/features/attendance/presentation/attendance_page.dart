import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../../shared/widgets/page_controls.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../../members/presentation/member_components.dart' show MemberError;
import '../data/attendance_failure.dart';
import '../models/attendance_models.dart';
import '../providers/attendance_providers.dart';

class AttendanceError extends StatelessWidget {
  const AttendanceError({super.key, required this.error, this.retry});
  final Object? error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(
          error is AttendanceFailure
              ? (error as AttendanceFailure).message
              : 'Attendance could not be loaded. Please try again.',
        ),
      ),
      if (retry != null)
        TextButton(onPressed: retry, child: const Text('Retry')),
    ],
  );
}

class AttendancePageView extends ConsumerStatefulWidget {
  const AttendancePageView({super.key});
  @override
  ConsumerState<AttendancePageView> createState() => _AttendancePageViewState();
}

class _AttendancePageViewState extends ConsumerState<AttendancePageView> {
  int _openPage = 1, _todayPage = 1;
  VisitStatus? _status = VisitStatus.completed;
  AdminGymContext? _gym;
  AttendanceVisit? _confirm;
  MemberProfile? _filter;
  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (_gym != gym) {
      _gym = gym;
      _openPage = _todayPage = 1;
      _confirm = null;
      _filter = null;
      _status = VisitStatus.completed;
    }
    final openRequest = (gym: gym, page: _openPage);
    final todayRequest = (
      gym: gym,
      page: _todayPage,
      status: _status,
      memberId: _filter?.id,
    );
    final open = ref.watch(openAttendanceProvider(openRequest));
    final today = ref.watch(attendanceTodayProvider(todayRequest));
    final mutation = ref.watch(attendanceMutationProvider(gym));
    final blocked =
        mutation.error is AttendanceFailure &&
        (mutation.error as AttendanceFailure).uncertain;
    Future<void> refresh() async {
      ref.invalidate(openAttendanceProvider(openRequest));
      ref.invalidate(attendanceTodayProvider(todayRequest));
      await Future.wait([
        ref
            .read(openAttendanceProvider(openRequest).future)
            .then<void>((_) {}, onError: (Object _) {}),
        ref
            .read(attendanceTodayProvider(todayRequest).future)
            .then<void>((_) {}, onError: (Object _) {}),
      ]);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Attendance Today',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh attendance',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (today.asData?.value case final AttendanceToday data)
            Text('Gym day: ${data.date} · ${data.timezone}'),
          const Text('All branches'),
          const Text(
            'Times below are displayed in your device timezone. Gym today is resolved by the server.',
          ),
          FilledButton(
            onPressed: mutation.isLoading || blocked
                ? null
                : () => context.push(
                    '${AppRoutes.attendance}/check-in?gymId=${Uri.encodeQueryComponent(gym.gymId)}',
                  ),
            child: const Text('Check in member'),
          ),
          if (mutation.hasError)
            AttendanceError(
              key: const ValueKey('attendanceMutationError'),
              error: mutation.error,
            ),
          if (blocked)
            OutlinedButton(
              onPressed: mutation.isLoading
                  ? null
                  : () async {
                      final checked = await ref
                          .read(attendanceMutationProvider(gym).notifier)
                          .recheck();
                      if (checked && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Attendance refreshed. Verify open visits and today’s visits before another action.',
                            ),
                          ),
                        );
                      }
                    },
              child: const Text('Recheck attendance'),
            ),
          if (mutation.asData?.value case final AttendanceVisit visit)
            ProfileSection(
              title: 'Server confirmation',
              children: [
                Text('Visit ${visit.status.name}'),
                Text('Checked in: ${formatVisitTime(visit.checkInAt)}'),
                if (visit.checkOutAt != null)
                  Text('Checked out: ${formatVisitTime(visit.checkOutAt!)}'),
                if (visit.durationMs != null)
                  Text('Duration: ${formatVisitDuration(visit.durationMs!)}'),
              ],
            ),
          ProfileSection(
            title: 'Currently checked in',
            children: [
              const Text(
                'Open visits across all dates, including overnight visits.',
              ),
              if (open.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (open.hasError)
                AttendanceError(
                  error: open.error,
                  retry: () =>
                      ref.invalidate(openAttendanceProvider(openRequest)),
                )
              else if (open.asData?.value case final AttendancePage data) ...[
                if (data.visits.isEmpty) const Text('No open visits.'),
                ...data.visits.map(
                  (visit) => _OpenVisitCard(
                    gym: gym,
                    visit: visit,
                    checkOut: mutation.isLoading || blocked
                        ? null
                        : () => setState(() => _confirm = visit),
                  ),
                ),
                PageControls(
                  page: data.pagination.page,
                  total: data.pagination.total,
                  previous: data.pagination.hasPrevious
                      ? () => setState(() => _openPage--)
                      : null,
                  next: data.pagination.hasNext
                      ? () => setState(() => _openPage++)
                      : null,
                ),
              ],
            ],
          ),
          if (_confirm case final AttendanceVisit visit)
            ProfileSection(
              title: 'Confirm check-out',
              children: [
                Text(
                  'Close the open visit checked in at ${formatVisitTime(visit.checkInAt)}? The server records checkout time and duration.',
                ),
                FilledButton(
                  onPressed: mutation.isLoading || blocked
                      ? null
                      : () async {
                          await ref
                              .read(attendanceMutationProvider(gym).notifier)
                              .checkOut(visit.id);
                          if (!mounted || ref.read(adminGymProvider) != gym) {
                            return;
                          }
                          setState(() => _confirm = null);
                        },
                  child: const Text('Confirm check-out'),
                ),
                TextButton(
                  onPressed: mutation.isLoading
                      ? null
                      : () => setState(() => _confirm = null),
                  child: const Text('Keep checked in'),
                ),
              ],
            ),
          ProfileSection(
            title: 'Today’s visits',
            children: [
              OutlinedButton(
                onPressed: () async {
                  final selected = await context.push<MemberProfile>(
                    '${AppRoutes.attendance}/check-in?gymId=${Uri.encodeQueryComponent(gym.gymId)}&mode=filter',
                  );
                  if (!mounted ||
                      ref.read(adminGymProvider) != gym ||
                      selected == null) {
                    return;
                  }
                  setState(() {
                    _filter = selected;
                    _todayPage = 1;
                  });
                },
                child: Text(
                  _filter == null
                      ? 'Filter today by member'
                      : 'Member: ${_filter!.name}',
                ),
              ),
              if (_filter != null)
                TextButton(
                  onPressed: () => setState(() {
                    _filter = null;
                    _todayPage = 1;
                  }),
                  child: const Text('Clear member filter'),
                ),

              DropdownButtonFormField<String>(
                key: ValueKey('attendanceStatus:${gym.gymId}'),
                initialValue: _status?.name ?? 'all',
                decoration: const InputDecoration(labelText: 'Visit status'),
                items: ['all', 'open', 'completed']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _status = value == 'all'
                      ? null
                      : VisitStatus.values.byName(value!);
                  _todayPage = 1;
                }),
              ),
              if (today.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (today.hasError)
                AttendanceError(
                  error: today.error,
                  retry: () =>
                      ref.invalidate(attendanceTodayProvider(todayRequest)),
                )
              else if (today.asData?.value case final AttendanceToday data) ...[
                Text(
                  'Matching visits: ${data.summary.total} · Unique members: ${data.summary.uniqueMembers}',
                ),
                Text(
                  'Matching completed: ${data.summary.completed} · Matching open today: ${data.summary.open}',
                ),
                if (data.visits.isEmpty)
                  const Text('No matching visits today.'),
                ...data.visits.map(
                  (visit) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${visit.memberName} · ${visit.memberCode}'),
                        Text(
                          'Branch: ${visit.branchName} · ${visit.status.name}',
                        ),
                        Text('In: ${formatVisitTime(visit.checkInAt)}'),
                        if (visit.checkOutAt != null)
                          Text('Out: ${formatVisitTime(visit.checkOutAt!)}'),
                        if (visit.durationMs != null)
                          Text(
                            'Duration: ${formatVisitDuration(visit.durationMs!)}',
                          ),
                      ],
                    ),
                  ),
                ),
                PageControls(
                  page: data.pagination.page,
                  total: data.pagination.total,
                  previous: data.pagination.hasPrevious
                      ? () => setState(() => _todayPage--)
                      : null,
                  next: data.pagination.hasNext
                      ? () => setState(() => _todayPage++)
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OpenVisitCard extends ConsumerWidget {
  const _OpenVisitCard({
    required this.gym,
    required this.visit,
    required this.checkOut,
  });
  final AdminGymContext gym;
  final AttendanceVisit visit;
  final VoidCallback? checkOut;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = memberProfileProvider(scopeFor(gym, visit.memberId));
    final member = ref.watch(request);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.asData?.value case final MemberProfile profile)
            Text('${profile.name} · ${profile.memberCode}')
          else if (member.hasError)
            MemberError(
              error: member.error,
              retry: () => ref.invalidate(request),
            )
          else
            const Text('Loading member identity…'),
          Text('Branch ID: ${visit.branchId}'),
          Text('Checked in: ${formatVisitTime(visit.checkInAt)}'),
          OutlinedButton(onPressed: checkOut, child: const Text('Check out')),
        ],
      ),
    );
  }
}
