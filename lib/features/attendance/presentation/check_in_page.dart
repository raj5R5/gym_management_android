import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/profile_section.dart';
import '../../../shared/widgets/page_controls.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../members/models/member_models.dart';
import '../../members/presentation/member_components.dart' show MemberError;
import '../data/attendance_failure.dart';
import '../providers/attendance_providers.dart';
import 'attendance_page.dart' show AttendanceError;

class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({super.key, required this.gymId, this.selectOnly = false});
  final String? gymId;
  final bool selectOnly;
  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  int _page = 1;
  MemberProfile? _selected;
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CheckInPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gymId != widget.gymId ||
        oldWidget.selectOnly != widget.selectOnly) {
      _query = '';
      _page = 1;
      _selected = null;
      _search.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(adminGymProvider);
    if (gym == null) return const SizedBox.shrink();
    if (gym.gymId != widget.gymId) {
      return Center(
        child: TextButton(
          onPressed: () => context.go(AppRoutes.attendance),
          child: const Text('Gym changed. Return to Attendance.'),
        ),
      );
    }
    final request = (gym: gym, search: _query, page: _page);
    final members = ref.watch(attendanceMembersProvider(request));
    final mutation = ref.watch(attendanceMutationProvider(gym));
    final blocked =
        mutation.error is AttendanceFailure &&
        (mutation.error as AttendanceFailure).uncertain;
    final busy = mutation.isLoading;
    return PopScope(
      canPop: !busy,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to Attendance',
                onPressed: busy
                    ? null
                    : () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.attendance);
                        }
                      },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.selectOnly ? 'Select member' : 'Check in member',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (!widget.selectOnly)
            const Text(
              'Check-in uses the member’s existing assigned branch. The server checks eligibility; branch selection is not available.',
            ),
          if (mutation.hasError && !widget.selectOnly)
            AttendanceError(error: mutation.error),
          if (blocked && !widget.selectOnly)
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.attendance),
              child: const Text('Verify attendance first'),
            ),
          if (_selected case final MemberProfile member)
            ProfileSection(
              title: 'Confirm check-in',
              children: [
                Text('${member.name} · ${member.memberCode}'),
                const Text(
                  'The server records check-in time and validates the current membership and assigned branch.',
                ),
                if (busy) const Center(child: CircularProgressIndicator()),
                FilledButton(
                  onPressed: busy || blocked
                      ? null
                      : () async {
                          final result = await ref
                              .read(attendanceMutationProvider(gym).notifier)
                              .checkIn(member.id);
                          if (!context.mounted ||
                              ref.read(adminGymProvider) != gym) {
                            return;
                          }
                          if (result != null) {
                            context.go(AppRoutes.attendance);
                          } else {
                            setState(() => _selected = null);
                            if (_scroll.hasClients) {
                              _scroll.jumpTo(0);
                            }
                          }
                        },
                  child: const Text('Confirm check-in'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _selected = null),
                  child: const Text('Choose another member'),
                ),
              ],
            )
          else ...[
            TextField(
              key: const ValueKey('attendanceMemberSearch'),
              controller: _search,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Search name, member code or phone',
              ),
              onSubmitted: (value) => setState(() {
                _query = value.trim();
                _page = 1;
              }),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _query = _search.text.trim();
                      _page = 1;
                    }),
              child: const Text('Search members'),
            ),
            if (members.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (members.hasError)
              MemberError(
                error: members.error,
                retry: () => ref.invalidate(attendanceMembersProvider(request)),
              )
            else if (members.asData?.value case final MembersPage data) ...[
              if (data.members.isEmpty) const Text('No matching members.'),
              ...data.members.map(
                (member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.name),
                  subtitle: Text(
                    '${member.memberCode} · ${member.phone} · ${member.status.name}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy || blocked && !widget.selectOnly
                      ? null
                      : () {
                          if (widget.selectOnly) {
                            context.pop(member);
                          } else {
                            setState(() => _selected = member);
                          }
                        },
                ),
              ),
              PageControls(
                page: data.pagination.page,
                total: data.pagination.total,
                previous: data.pagination.hasPrevious
                    ? () => setState(() => _page--)
                    : null,
                next: data.pagination.hasNext
                    ? () => setState(() => _page++)
                    : null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
