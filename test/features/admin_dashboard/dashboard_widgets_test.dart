import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import '../auth/auth_fakes.dart';
import '../members/member_fakes.dart';
import 'dashboard_fakes.dart';

void main() {
  Future<ProviderContainer> pumpAdmin(
    WidgetTester tester,
    FakeDashboardRepository repository, {
    AuthRole role = AuthRole.admin,
    bool authenticated = true,
    List<String> gyms = const [gymA],
  }) async {
    final api = FakeAuthApi()..identity = adminIdentity(gyms: gyms, role: role);
    final scope = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(repository),
        memberRepositoryProvider.overrideWithValue(
          FakeMemberRepository()..empty = true,
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scope, child: const GymApp()),
    );
    await tester.pump();
    return scope;
  }

  testWidgets(
    'admin enters real dashboard shell with all-branch context and period',
    (tester) async {
      final repository = FakeDashboardRepository();
      final scope = await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
        AppRoutes.dashboard,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Whole gym · All branches'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('2026-03-01 to 2026-03-01 · Inclusive'), findsOneWidget);
      expect(find.text('Gym timezone: Asia/Kolkata'), findsOneWidget);
      expect(repository.requests.single.gymId, gymA);
      await tester.scrollUntilVisible(find.text('Successful revenue'), 250);
      expect(find.text('₹12,34,567.89'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Checked in now'), 200);
      expect(find.text('Checked in now'), findsOneWidget);
    },
  );
  testWidgets('admin login redirects to dashboard without manual navigation', (
    tester,
  ) async {
    final repository = FakeDashboardRepository();
    final scope = await pumpAdmin(tester, repository, authenticated: false);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.invalid',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      syntheticCredential(),
    );
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(repository.requests.length, 1);
    scope.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
    expect(repository.requests.length, 1);
  });
  testWidgets(
    'dashboard loading then zero metrics have an explicit empty state',
    (tester) async {
      final repository = FakeDashboardRepository()
        ..gate = Completer<GymDashboard>();
      await pumpAdmin(tester, repository);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.gate!.complete(
        GymDashboard.fromJson(dashboardJson(empty: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No dashboard activity to show. All metrics are zero.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Successful revenue'), 250);
      expect(find.text('₹0.00'), findsOneWidget);
    },
  );
  testWidgets('safe error supports retry and explicit refresh', (tester) async {
    final repository = FakeDashboardRepository()
      ..failure = const AuthFailure(AuthFailureKind.network);
    await pumpAdmin(tester, repository);
    await tester.pumpAndSettle();
    expect(
      find.text(const AuthFailure(AuthFailureKind.network).message),
      findsOneWidget,
    );
    repository.failure = null;
    await tester.tap(find.text('Retry dashboard'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 2);
    await tester.tap(find.byTooltip('Refresh dashboard'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 3);
  });
  testWidgets(
    'members section, trainer placeholder, back to dashboard, more/logout',
    (tester) async {
      final scope = await pumpAdmin(tester, FakeDashboardRepository());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Members').last);
      await tester.pumpAndSettle();
      expect(
        find.text('No members yet. Add your first member.'),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
        AppRoutes.dashboard,
      );
      await tester.tap(find.text('Trainers').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Trainers will be available in a later milestone.'),
        findsOneWidget,
      );
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );
  testWidgets('trainer cannot navigate into admin shell or call dashboard', (
    tester,
  ) async {
    final repository = FakeDashboardRepository();
    final scope = await pumpAdmin(tester, repository, role: AuthRole.trainer);
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(repository.requests, isEmpty);
  });
  testWidgets('unauthenticated admin deep link goes to login', (tester) async {
    final repository = FakeDashboardRepository();
    final scope = await pumpAdmin(tester, repository, authenticated: false);
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).go(AppRoutes.members);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(repository.requests, isEmpty);
  });
  testWidgets(
    'multi-gym selector is restricted to grants and changes request context',
    (tester) async {
      final repository = FakeDashboardRepository();
      final scope = await pumpAdmin(tester, repository, gyms: [gymA, gymB]);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      scope.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(repository.requests.last.gymId, gymB);
    },
  );
  testWidgets('failed session recovery removes the admin shell and dashboard', (
    tester,
  ) async {
    final repository = FakeDashboardRepository();
    final scope = await pumpAdmin(tester, repository);
    await tester.pumpAndSettle();
    final api = scope.read(authApiServiceProvider) as FakeAuthApi;
    api.refreshFailure = const AuthFailure(AuthFailureKind.invalidSession);
    await expectLater(
      scope.read(sessionControllerProvider.notifier).refreshSession(),
      throwsA(isA<AuthFailure>()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(await scope.read(dashboardProvider.future), isNull);
    expect(repository.requests.length, 1);
  });
  testWidgets('date picker opens without a branch selector', (tester) async {
    await pumpAdmin(tester, FakeDashboardRepository());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select period'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(
      find.text('Select period (up to 366 inclusive days)'),
      findsOneWidget,
    );
  });
  testWidgets('dashboard works at 320px width and larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpAdmin(tester, FakeDashboardRepository());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Successful revenue'), 250);
    expect(tester.takeException(), isNull);
  });
}
