import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/data/dashboard_repository.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import '../auth/auth_fakes.dart';
import 'dashboard_fakes.dart';

class PendingRepository implements DashboardRepository {
  final requests = <Completer<GymDashboard>>[];
  @override
  Future<GymDashboard> getDashboard(String gymId, DashboardQuery query) {
    final request = Completer<GymDashboard>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  late FakeAuthApi api;
  late FakeDashboardRepository repository;
  late ProviderContainer container;
  setUp(() {
    api = FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]);
    repository = FakeDashboardRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        dashboardRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());

  test('no session means no dashboard requests', () async {
    expect(await container.read(dashboardProvider.future), isNull);
    expect(repository.requests, isEmpty);
  });
  test(
    'loading transitions to typed successful metrics with explicit gym',
    () async {
      await login();
      repository.gate = Completer<GymDashboard>();
      final states = <AsyncValue<GymDashboard?>>[];
      container.listen(
        dashboardProvider,
        (_, state) => states.add(state),
        fireImmediately: true,
      );
      final result = container.read(dashboardProvider.future);
      expect(container.read(dashboardProvider).isLoading, isTrue);
      repository.gate!.complete(repository.result);
      await result;
      expect(states.first.isLoading, isTrue);
      expect(states.last.asData!.value!.members.total, 12);
      expect(repository.requests.single.gymId, gymA);
      expect(repository.requests.single.query.toParameters(), isEmpty);
    },
  );
  test('safe error state and retry recovers', () async {
    await login();
    repository.failure = const AuthFailure(AuthFailureKind.network);
    await expectLater(
      container.read(dashboardProvider.future),
      throwsA(isA<AuthFailure>()),
    );
    expect(container.read(dashboardProvider).hasError, isTrue);
    repository.failure = null;
    await container.read(dashboardProvider.notifier).reload();
    expect(container.read(dashboardProvider).asData!.value!.members.total, 12);
    expect(repository.requests.length, 2);
  });
  test(
    'date range provider drives new request; gym-local today resets',
    () async {
      await login();
      await container.read(dashboardProvider.future);
      final query = container.read(dashboardQueryProvider.notifier);
      query.selectRange(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 1));
      await container.read(dashboardProvider.future);
      expect(repository.requests.last.query.toParameters(), {
        'from': '2026-03-01',
        'to': '2026-03-01',
      });
      query.useGymToday();
      await container.read(dashboardProvider.future);
      expect(repository.requests.last.query.toParameters(), isEmpty);
    },
  );
  test(
    'invalid date selection does not replace valid filter or issue request',
    () async {
      await login();
      await container.read(dashboardProvider.future);
      expect(
        () => container
            .read(dashboardQueryProvider.notifier)
            .selectRange(CalendarDate(2025, 1, 1), CalendarDate(2026, 1, 2)),
        throwsFormatException,
      );
      expect(repository.requests.length, 1);
    },
  );
  test('gym switching only accepts session-derived admin grants', () async {
    await login();
    await container.read(dashboardProvider.future);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await container.read(dashboardProvider.future);
    expect(repository.requests.last.gymId, gymB);
    expect(
      () => container.read(adminGymProvider.notifier).selectGym('unknown'),
      throwsArgumentError,
    );
  });
  for (final scenario in [
    (role: AuthRole.trainer, status: AccountStatus.active),
    (role: AuthRole.admin, status: AccountStatus.suspended),
  ]) {
    test('no admin requests for ${scenario.role}/${scenario.status}', () async {
      api.identity = adminIdentity(
        role: scenario.role,
        status: scenario.status,
      );
      await login();
      expect(await container.read(dashboardProvider.future), isNull);
      expect(repository.requests, isEmpty);
    });
  }
  test(
    'refresh retains selected scope and filters without another dashboard operation',
    () async {
      await login();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      container
          .read(dashboardQueryProvider.notifier)
          .selectRange(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 1));
      await container.read(dashboardProvider.future);
      api.refreshGate = Completer<void>();
      final recovery = container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await api.refreshEntered.future;
      expect(container.read(adminGymProvider)!.gymId, gymB);
      await container.read(dashboardProvider.future);
      api.refreshGate!.complete();
      await recovery;
      await container.read(dashboardProvider.future);
      expect(repository.requests.length, 1);
      expect(container.read(adminGymProvider)!.gymId, gymB);
    },
  );
  test('logout removes scope and cached dashboard', () async {
    await login();
    await container.read(dashboardProvider.future);
    await container.read(sessionControllerProvider.notifier).logout();
    expect(await container.read(dashboardProvider.future), isNull);
    expect(container.read(adminGymProvider), isNull);
  });
  test('old gym response cannot replace newer gym metrics', () async {
    final pending = PendingRepository();
    final scope = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        dashboardRepositoryProvider.overrideWithValue(pending),
      ],
    );
    addTearDown(scope.dispose);
    await scope
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
    scope.listen(dashboardProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    scope.read(adminGymProvider.notifier).selectGym(gymB);
    final latest = scope.read(dashboardProvider.future);
    await Future<void>.delayed(Duration.zero);
    pending.requests[1].complete(
      GymDashboard.fromJson(dashboardJson(empty: true)),
    );
    await latest;
    pending.requests[0].complete(GymDashboard.fromJson(dashboardJson()));
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(dashboardProvider).asData!.value!.isEmpty, isTrue);
  });
  test(
    'changing presets ignores older completions and retains the latest filter',
    () async {
      final pending = PendingRepository();
      final scope = ProviderContainer(
        overrides: [
          authApiServiceProvider.overrideWithValue(api),
          credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
          dashboardRepositoryProvider.overrideWithValue(pending),
        ],
      );
      addTearDown(scope.dispose);
      await scope
          .read(sessionControllerProvider.notifier)
          .login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
      scope.listen(dashboardProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      scope
          .read(dashboardQueryProvider.notifier)
          .selectPreset(DashboardDateFilter.last7Days);
      scope.read(dashboardProvider.future);
      await Future<void>.delayed(Duration.zero);
      scope
          .read(dashboardQueryProvider.notifier)
          .selectPreset(DashboardDateFilter.thisMonth);
      final latest = scope.read(dashboardProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(pending.requests, hasLength(3));
      pending.requests[2].complete(
        GymDashboard.fromJson(dashboardJson(revenue: 300000)),
      );
      await latest;
      pending.requests[1].complete(
        GymDashboard.fromJson(dashboardJson(revenue: 100000)),
      );
      pending.requests[0].complete(
        GymDashboard.fromJson(dashboardJson(revenue: 0)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        scope
            .read(dashboardProvider)
            .asData!
            .value!
            .payments
            .periodSuccessfulAmountPaise,
        300000,
      );
      expect(
        scope.read(dashboardQueryProvider).filter,
        DashboardDateFilter.thisMonth,
      );
    },
  );
}
