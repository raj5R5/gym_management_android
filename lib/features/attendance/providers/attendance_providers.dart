import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../../members/data/member_failure.dart';
import '../../members/models/member_models.dart';
import '../../members/providers/member_providers.dart';
import '../data/attendance_failure.dart';
import '../data/attendance_repository.dart';
import '../models/attendance_models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => DioAttendanceRepository(ref.watch(authenticatedApiClientProvider)),
);
typedef TodayRequest = ({
  AdminGymContext gym,
  int page,
  VisitStatus? status,
  String? memberId,
});
typedef OpenRequest = ({AdminGymContext gym, int page});
final attendanceTodayProvider = FutureProvider.autoDispose
    .family<AttendanceToday?, TodayRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(attendanceRepositoryProvider)
          .today(
            request.gym.gymId,
            AttendanceQuery(
              page: request.page,
              status: request.status,
              memberId: request.memberId,
            ),
          );
    }, retry: (_, _) => null);
final openAttendanceProvider = FutureProvider.autoDispose
    .family<AttendancePage?, OpenRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(attendanceRepositoryProvider)
          .openVisits(request.gym.gymId, request.page);
    }, retry: (_, _) => null);
typedef MemberSearchRequest = ({AdminGymContext gym, String search, int page});
final attendanceMembersProvider = FutureProvider.autoDispose
    .family<MembersPage?, MemberSearchRequest>((ref, request) {
      if (ref.watch(adminGymProvider) != request.gym) return null;
      return ref
          .watch(memberRepositoryProvider)
          .list(
            request.gym.gymId,
            MemberListQuery(page: request.page, search: request.search),
          );
    }, retry: (_, _) => null);

class AttendanceMutationController extends AsyncNotifier<AttendanceVisit?> {
  AttendanceMutationController(this.gym);
  final AdminGymContext gym;
  bool _busy = false;
  int? _revision;
  AttendanceFailure? _locked;
  @override
  AttendanceVisit? build() {
    final context = ref.watch(adminGymProvider);
    final revision = ref.read(authRepositoryProvider).revision;
    if (_revision != revision) {
      _revision = revision;
      _locked = null;
    }
    if (context == gym && _locked != null) throw _locked!;
    return null;
  }

  bool _current(int revision) =>
      ref.mounted &&
      ref.read(adminGymProvider) == gym &&
      ref.read(sessionControllerProvider) is SessionAuthenticated &&
      ref.read(authRepositoryProvider).revision == revision;
  void _invalidate() {
    ref.invalidate(attendanceTodayProvider);
    ref.invalidate(openAttendanceProvider);
    ref.invalidate(memberSummaryProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<AttendanceVisit?> _run(
    Future<AttendanceVisit> Function(AttendanceRepository, bool Function())
    send,
  ) async {
    final revision = ref.read(authRepositoryProvider).revision;
    if (_busy || _locked != null || !_current(revision)) return null;
    _busy = true;
    state = const AsyncLoading();
    try {
      final visit = await send(
        ref.read(attendanceRepositoryProvider),
        () => _current(revision),
      );
      if (!_current(revision)) return null;
      _invalidate();
      state = AsyncData(visit);
      return visit;
    } catch (error, stack) {
      if (_current(revision)) {
        final failure = error is AttendanceFailure
            ? error
            : error is MemberFailure
            ? AttendanceFailure(error.message)
            : const AttendanceFailure(
                'The attendance outcome is uncertain. Recheck attendance before another attempt.',
                uncertain: true,
                recheck: true,
              );
        if (failure.uncertain) _locked = failure;
        if (failure.recheck) _invalidate();
        state = AsyncError(failure, stack);
      }
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<AttendanceVisit?> checkIn(String memberId) =>
      _run((repository, current) async {
        final member = await ref
            .read(memberRepositoryProvider)
            .get(gym.gymId, memberId);
        // Do not send a write if account/gym changed during the profile read.
        if (!current()) {
          throw const AttendanceFailure('The session or gym changed.');
        }
        return repository.checkIn(gym.gymId, member);
      });
  Future<AttendanceVisit?> checkOut(String visitId) =>
      _run((repository, _) => repository.checkOut(gym.gymId, visitId));
  Future<bool> recheck() async {
    final revision = ref.read(authRepositoryProvider).revision;
    if (_busy || !_current(revision)) return false;
    _busy = true;
    state = const AsyncLoading();
    try {
      final repository = ref.read(attendanceRepositoryProvider);
      await repository.openVisits(gym.gymId, 1);
      if (!_current(revision)) return false;
      await repository.today(gym.gymId, AttendanceQuery());
      if (!_current(revision)) return false;
      _locked = null;
      _invalidate();
      state = const AsyncData(null);
      return true;
    } catch (_, stack) {
      if (_current(revision)) {
        _locked = const AttendanceFailure(
          'Attendance could not be checked. Recheck before another attempt.',
          uncertain: true,
          recheck: true,
        );
        state = AsyncError(_locked!, stack);
      }
      return false;
    } finally {
      _busy = false;
    }
  }
}

final attendanceMutationProvider =
    AsyncNotifierProvider.family<
      AttendanceMutationController,
      AttendanceVisit?,
      AdminGymContext
    >(AttendanceMutationController.new, retry: (_, _) => null);
