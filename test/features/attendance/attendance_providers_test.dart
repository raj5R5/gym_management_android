import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/attendance/providers/attendance_providers.dart';
import 'package:gym_management_app/features/attendance/data/attendance_failure.dart';
import 'package:gym_management_app/features/attendance/models/attendance_models.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'attendance_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeAttendanceRepository repository;
  late AttendanceMemberRepository members;
  setUp(() {
    repository = FakeAttendanceRepository();
    members = AttendanceMemberRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        attendanceRepositoryProvider.overrideWithValue(repository),
        memberRepositoryProvider.overrideWithValue(members),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());
  TodayRequest request() => (
    gym: container.read(adminGymProvider)!,
    page: 1,
    status: null,
    memberId: null,
  );
  test('unauthenticated scope cannot read or mutate', () async {
    final gym = (userId: 'none', gymId: gymA);
    expect(
      await container.read(openAttendanceProvider((gym: gym, page: 1)).future),
      isNull,
    );
    expect(
      await container
          .read(attendanceMutationProvider(gym).notifier)
          .checkOut(visitId),
      isNull,
    );
    expect(repository.calls, isEmpty);
  });
  test('loading then server today state', () async {
    await login();
    final current = request();
    repository.todayGate = Completer<AttendanceToday>();
    final pending = container.read(attendanceTodayProvider(current).future);
    expect(container.read(attendanceTodayProvider(current)).isLoading, isTrue);
    repository.todayGate!.complete(
      AttendanceToday.fromResponse(todayJson(), {
        'pagination': {'page': 1, 'limit': 20, 'total': 1},
      }),
    );
    expect((await pending)!.summary.completed, 1);
  });
  test(
    'error, retry, empty and refresh use explicit invalidation only',
    () async {
      await login();
      final current = request();
      repository.failure = const AttendanceFailure('Offline');
      container.listen(attendanceTodayProvider(current), (_, _) {});
      await expectLater(
        container.read(attendanceTodayProvider(current).future),
        throwsA(isA<AttendanceFailure>()),
      );
      repository.failure = null;
      repository.empty = true;
      container.invalidate(attendanceTodayProvider(current));
      expect(
        (await container.read(attendanceTodayProvider(current).future))!.visits,
        isEmpty,
      );
      repository.empty = false;
      container.invalidate(attendanceTodayProvider(current));
      expect(
        (await container.read(
          attendanceTodayProvider(current).future,
        ))!.visits.length,
        1,
      );
      expect(repository.queries.length, 3);
    },
  );
  test('pagination and trusted member filter reach backend', () async {
    await login();
    final gym = request().gym;
    await container.read(
      attendanceTodayProvider((
        gym: gym,
        page: 2,
        status: VisitStatus.completed,
        memberId: memberId,
      )).future,
    );
    expect(repository.queries.single.toParameters(), {
      'page': '2',
      'limit': '20',
      'status': 'completed',
      'memberId': memberId,
    });
  });
  test('stale today response cannot publish after gym switch', () async {
    await login();
    final current = request();
    repository.todayGate = Completer<AttendanceToday>();
    container.listen(attendanceTodayProvider(current), (_, _) {});
    container.read(attendanceTodayProvider(current).future);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    expect(
      await container.read(attendanceTodayProvider(current).future),
      isNull,
    );
    repository.todayGate!.complete(
      AttendanceToday.fromResponse(todayJson(), {
        'pagination': {'page': 1, 'limit': 20, 'total': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(attendanceTodayProvider(current)).asData!.value,
      isNull,
    );
  });
  test(
    'fresh member preflight then check-in; duplicate writes suppressed',
    () async {
      await login();
      final gym = request().gym;
      repository.writeGate = Completer<AttendanceVisit>();
      final controller = container.read(
        attendanceMutationProvider(gym).notifier,
      );
      final pending = controller.checkIn(memberId);
      await Future<void>.delayed(Duration.zero);
      expect(await controller.checkIn(memberId), isNull);
      expect(repository.writes, 1);
      expect(members.operations, contains('get:$gymA:$memberId'));
      repository.writeGate!.complete(AttendanceVisit.fromJson(visitJson()));
      expect(await pending, isNotNull);
    },
  );
  for (final change in ['gym', 'logout-relogin']) {
    test('no write after $change while reading member branch', () async {
      await login();
      final gym = request().gym;
      members.getGate = Completer<MemberProfile>();
      container.listen(attendanceMutationProvider(gym), (_, _) {});
      final pending = container
          .read(attendanceMutationProvider(gym).notifier)
          .checkIn(memberId);
      if (change == 'gym') {
        container.read(adminGymProvider.notifier).selectGym(gymB);
      } else {
        await container.read(sessionControllerProvider.notifier).logout();
        await login();
      }
      members.getGate!.complete(
        MemberProfile.fromJson(profileJson()..['branchId'] = branchId),
      );
      expect(await pending, isNull);
      expect(repository.writes, 0);
    });
  }
  test(
    'check-in and checkout rejection are safe without local visit fabrication',
    () async {
      await login();
      final gym = request().gym;
      final controller = container.read(
        attendanceMutationProvider(gym).notifier,
      );
      repository.failure = const AttendanceFailure('Membership required');
      expect(await controller.checkIn(memberId), isNull);
      expect(container.read(attendanceMutationProvider(gym)).hasError, isTrue);
      repository.failure = const AttendanceFailure(
        'Visit closed',
        recheck: true,
      );
      expect(await controller.checkOut(visitId), isNull);
    },
  );
  test(
    'checkout success invalidates open list and preserves server duration',
    () async {
      await login();
      final gym = request().gym;
      final open = openAttendanceProvider((gym: gym, page: 1));
      container.listen(open, (_, _) {});
      expect((await container.read(open.future))!.visits.length, 1);
      final closed = await container
          .read(attendanceMutationProvider(gym).notifier)
          .checkOut(visitId);
      expect(closed!.durationMs, 4500000);
      expect((await container.read(open.future))!.visits, isEmpty);
    },
  );
  test(
    'uncertain write blocks actions until both attendance reads recheck',
    () async {
      await login();
      final gym = request().gym;
      final controller = container.read(
        attendanceMutationProvider(gym).notifier,
      );
      repository.failure = const AttendanceFailure(
        'Unknown outcome',
        uncertain: true,
        recheck: true,
      );
      await controller.checkOut(visitId);
      repository.failure = null;
      expect(await controller.checkOut(visitId), isNull);
      expect(await controller.checkIn(memberId), isNull);
      expect(repository.writes, 1);
      expect(await controller.recheck(), isTrue);
      expect(repository.calls, contains('open:$gymA:1'));
      expect(repository.calls, contains('today:$gymA:1'));
      expect(await controller.checkOut(visitId), isNotNull);
    },
  );
  test('failed recheck keeps uncertain lock', () async {
    await login();
    final controller = container.read(
      attendanceMutationProvider(request().gym).notifier,
    );
    repository.failure = const AttendanceFailure(
      'Unknown outcome',
      uncertain: true,
      recheck: true,
    );
    await controller.checkOut(visitId);
    expect(await controller.recheck(), isFalse);
    repository.failure = null;
    expect(await controller.checkOut(visitId), isNull);
    expect(repository.writes, 1);
  });
  test('pending write ignored after logout', () async {
    await login();
    final gym = request().gym;
    repository.writeGate = Completer<AttendanceVisit>();
    container.listen(attendanceMutationProvider(gym), (_, _) {});
    final pending = container
        .read(attendanceMutationProvider(gym).notifier)
        .checkOut(visitId);
    await container.read(sessionControllerProvider.notifier).logout();
    repository.writeGate!.complete(
      AttendanceVisit.fromJson(visitJson(completed: true)),
    );
    expect(await pending, isNull);
  });
}
