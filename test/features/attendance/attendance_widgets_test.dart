import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/attendance/data/attendance_failure.dart';
import 'package:gym_management_app/features/attendance/providers/attendance_providers.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/shared/widgets/profile_section.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'attendance_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeAttendanceRepository repository;
  late FakeAuthApi api;
  late AttendanceMemberRepository members;
  Future<void> pump(
    WidgetTester tester, {
    bool authenticated = true,
    AuthRole role = AuthRole.admin,
  }) async {
    repository = FakeAttendanceRepository();
    members = AttendanceMemberRepository();
    api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        attendanceRepositoryProvider.overrideWithValue(repository),
        memberRepositoryProvider.overrideWithValue(members),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GymApp()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go(AppRoutes.attendance);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('today and all-date open visits use distinct honest contexts', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Attendance Today'), findsOneWidget);
    expect(
      find.textContaining('2026-10-08 · America/New_York'),
      findsOneWidget,
    );
    expect(find.text('Currently checked in'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ProfileSection, 'Currently checked in'),
        matching: find.text('Alex River · ME01'),
      ),
      findsOneWidget,
    );
    await reveal(tester, find.text('Today’s visits'));
    await reveal(tester, find.text('Duration: 1h 15m 0s'));
    expect(find.text('Branch: Main · completed'), findsOneWidget);
  });
  testWidgets('check-in member search requires explicit confirmation', (
    tester,
  ) async {
    await pump(tester);
    repository.opened = false;
    await tap(tester, find.widgetWithText(FilledButton, 'Check in member'));
    await tester.enterText(
      find.byKey(const ValueKey('attendanceMemberSearch')),
      ' Alex ',
    );
    await tap(tester, find.widgetWithText(OutlinedButton, 'Search members'));
    expect(members.listCalls.last.query.search, 'Alex');
    await tap(tester, find.widgetWithText(ListTile, 'Alex River'));
    expect(repository.writes, 0);
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm check-in'));
    expect(repository.writes, 1);
    expect(find.text('Attendance Today'), findsOneWidget);
    expect(find.text('Visit open'), findsOneWidget);
  });
  testWidgets(
    'checkout confirmation closes visit and refreshes completed history',
    (tester) async {
      await pump(tester);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Check out'));
      expect(repository.writes, 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm check-out'));
      expect(repository.writes, 1);
      await reveal(tester, find.text('No open visits.'));
      await reveal(tester, find.text('Today’s visits'));
      expect(find.text('Branch: Main · completed'), findsOneWidget);
    },
  );
  testWidgets('empty and error states allow safe retry and refresh', (
    tester,
  ) async {
    await pump(tester);
    repository.empty = true;
    container.invalidate(openAttendanceProvider);
    container.invalidate(attendanceTodayProvider);
    await tester.pumpAndSettle();
    expect(find.text('No open visits.'), findsOneWidget);
    await reveal(tester, find.text('No matching visits today.'));
    repository.failure = const AttendanceFailure('Safe offline message');
    container.invalidate(attendanceTodayProvider);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Safe offline message'));
    repository.failure = null;
    await tap(tester, find.widgetWithText(TextButton, 'Retry'));
    expect(find.text('No matching visits today.'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1000));
    await tester.pumpAndSettle();
  });
  testWidgets('member filter and status dropdown narrow server query', (
    tester,
  ) async {
    await pump(tester);
    await tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Filter today by member'),
    );
    await tap(tester, find.widgetWithText(ListTile, 'Alex River'));
    expect(repository.writes, 0);
    expect(repository.queries.last.memberId, '000000000000000000000011');
    await tap(tester, find.byKey(const ValueKey('attendanceStatus:$gymA')));
    await tester.tap(find.text('all').last);
    await tester.pumpAndSettle();
    expect(repository.queries.last.status, isNull);
  });
  testWidgets('uncertain checkout never resubmits and offers recheck', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Check out'));
    repository.failure = const AttendanceFailure(
      'Verify attendance first',
      uncertain: true,
      recheck: true,
    );
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm check-out'));
    expect(repository.writes, 1);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attendanceMutationError')),
        matching: find.text('Verify attendance first'),
      ),
      findsOneWidget,
    );
    repository.failure = null;
    await tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Recheck attendance'),
    );
    expect(repository.writes, 1);
    expect(find.text('Verify attendance first'), findsNothing);
  });
  testWidgets(
    'normal Admin navigation hides Attendance and More logout works',
    (tester) async {
      await pump(tester);
      container.read(appRouterProvider).go(AppRoutes.dashboard);
      await tester.pumpAndSettle();
      repository.calls.clear();
      expect(find.byTooltip('Attendance'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.tap(find.byTooltip('Admin navigation'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Attendance'), findsNothing);
      for (final label in [
        'Dashboard',
        'Members',
        'Trainers',
        'Plans',
        'More',
      ]) {
        expect(find.widgetWithText(ListTile, label), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(ListTile, 'More'));
      await tester.pumpAndSettle();
      expect(find.text('Logout'), findsOneWidget);
      expect(repository.calls, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
    },
  );
  testWidgets('unauthenticated and trainer attendance routes are protected', (
    tester,
  ) async {
    await pump(tester, authenticated: false);
    expect(repository.calls, isEmpty);
    expect(find.text('Sign in to your account'), findsOneWidget);
    api.identity = adminIdentity(gyms: [gymA], role: AuthRole.trainer);
    await container
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
    container.read(appRouterProvider).go(AppRoutes.attendance);
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
  });
  testWidgets(
    'check-in selection survives session refresh and back returns attendance',
    (tester) async {
      await pump(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Check in member'));
      await tap(tester, find.widgetWithText(ListTile, 'Alex River'));
      api.refreshGate = Completer<void>();
      final pending = container.read(authRepositoryProvider).refreshSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Confirm check-in'), findsNothing);
      api.refreshGate!.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Confirm check-in'),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Back to Attendance'));
      expect(find.text('Attendance Today'), findsOneWidget);
      expect(repository.writes, 0);
    },
  );
  testWidgets('front desk fits 320px phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await reveal(tester, find.text('Today’s visits'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('branchless check-in shows a known failure without a write', (
    tester,
  ) async {
    await pump(tester);
    members.noBranch = true;
    await tap(tester, find.widgetWithText(FilledButton, 'Check in member'));
    await tap(tester, find.widgetWithText(ListTile, 'Alex River'));
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm check-in'));
    expect(find.text('This member has no assigned branch.'), findsOneWidget);
    expect(find.text('Verify attendance first'), findsNothing);
    expect(repository.writes, 0);
  });
  testWidgets('open visits paginate without changing the today period', (
    tester,
  ) async {
    await pump(tester);
    repository.total = 21;
    container.invalidate(openAttendanceProvider);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Next page').first);
    expect(repository.calls, contains('open:$gymA:2'));
    expect(repository.queries.every((query) => query.page == 1), isTrue);
  });
  testWidgets('attendance root back returns Dashboard without logging out', (
    tester,
  ) async {
    await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
    expect(find.byTooltip('Attendance'), findsNothing);
    // The parked route remains valid for future re-enablement and its tests.
    container.read(appRouterProvider).go(AppRoutes.attendance);
    await tester.pumpAndSettle();
    expect(find.text('Attendance Today'), findsOneWidget);
  });
}
