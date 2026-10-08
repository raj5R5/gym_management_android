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
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';

void main() {
  Future<ProviderContainer> pumpMembers(
    WidgetTester tester,
    FakeMemberRepository repository, {
    AuthRole role = AuthRole.admin,
    bool authenticated = true,
  }) async {
    final api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(repository),
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
    container.read(appRouterProvider).go(AppRoutes.members);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    return container;
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

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    for (final entry in {
      'memberCode': 'ME02',
      'firstName': 'Alex',
      'lastName': 'River',
      'phone': '+91 9876543210',
    }.entries) {
      await reveal(tester, find.byKey(ValueKey(entry.key)));
      await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
    }
  }

  testWidgets(
    'real member list renders identity/status and server pagination',
    (tester) async {
      final repository = FakeMemberRepository()..total = 21;
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.textContaining('ME01 · +91 9876543210'), findsOneWidget);
      expect(find.text('Page 1 · 21 total'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.page, 2);
      expect(find.text('Page 2 · 21 total'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.page, 1);
    },
  );
  testWidgets('empty list is actionable', (tester) async {
    await pumpMembers(tester, FakeMemberRepository()..empty = true);
    await tester.pumpAndSettle();
    expect(find.text('No members yet. Add your first member.'), findsOneWidget);
    expect(find.text('Add member'), findsOneWidget);
  });
  testWidgets('loading indicator while list request is pending', (
    tester,
  ) async {
    final repository = FakeMemberRepository()..delayLists = true;
    await pumpMembers(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pendingLists.single.complete(
      MembersPage(
        [],
        Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No members yet. Add your first member.'), findsOneWidget);
  });
  testWidgets('safe error retry and pull refresh', (tester) async {
    final repository = FakeMemberRepository()
      ..failure = const MemberFailure('Connection unavailable');
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Connection unavailable'), findsOneWidget);
    repository.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 2);
    await tester.drag(find.text('Members').first, const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 3);
  });
  testWidgets('search and status interaction send server filters', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Alex ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.search, 'Alex');
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inactive').last);
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.status, MemberStatus.inactive);
    expect(repository.listCalls.last.query.page, 1);
  });
  testWidgets(
    'details summary, membership history, cancellation details and back',
    (tester) async {
      final repository = FakeMemberRepository()..populated = true;
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(find.text('Member details'), findsOneWidget);
      expect(find.text('Branch: Central (active)'), findsOneWidget);
      expect(
        repository.operations.where((op) => op.startsWith('get:')),
        isEmpty,
      );
      await reveal(tester, find.text('Successful total: ₹3.03'));
      expect(find.text('Successful total: ₹3.03'), findsOneWidget);
      await reveal(tester, find.textContaining('Pat Lee'));
      expect(find.textContaining('Pat Lee'), findsOneWidget);
      await reveal(tester, find.text('View membership details'));
      await tester.tap(find.text('View membership details'));
      await tester.pumpAndSettle();
      expect(find.text('Reason: Requested'), findsOneWidget);
      expect(find.textContaining('Cancelled:'), findsOneWidget);
      await tester.tap(find.byTooltip('Close membership details'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.members,
      );
    },
  );
  testWidgets(
    'onboarding validates, omits branch/status, blocks duplicate and refetches',
    (tester) async {
      final repository = FakeMemberRepository();
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await openForm(tester);
      await reveal(tester, find.text('Create member'));
      await tester.tap(find.text('Create member'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–80 characters.'), findsNWidgets(2));
      expect(repository.writes, isEmpty);
      await fillRequired(tester);
      repository.saveGate = Completer<MemberProfile>();
      await reveal(tester, find.text('Create member'));
      await tester.tap(find.text('Create member'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(repository.writes.length, 1);
      expect(repository.writes.single.keys, isNot(contains('branchId')));
      expect(repository.writes.single.keys, isNot(contains('status')));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      repository.saveGate!.complete(MemberProfile.fromJson(profileJson()));
      await tester.pumpAndSettle();
      expect(find.text('Member created.'), findsOneWidget);
      expect(repository.listCalls.length, 2);
      expect(find.text('Add member'), findsOneWidget);
    },
  );
  testWidgets(
    'edit loads server profile and prevents immutable identity changes',
    (tester) async {
      final repository = FakeMemberRepository();
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit member'));
      await tester.pumpAndSettle();
      expect(
        find.text('Member code: ME01 (cannot be changed)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('memberCode')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Updated',
      );
      await reveal(tester, find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repository.writes.single['firstName'], 'Updated');
      expect(repository.writes.single.keys, isNot(contains('memberCode')));
      expect(find.text('Member updated.'), findsOneWidget);
      expect(find.text('Member details'), findsOneWidget);
    },
  );
  testWidgets('server duplicate validation remains in form for correction', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await openForm(tester);
    await fillRequired(tester);
    repository.failure = const MemberFailure(
      'That member code already exists in this gym. Choose another code.',
    );
    await reveal(tester, find.text('Create member'));
    await tester.tap(find.text('Create member'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('That member code already exists'),
      findsOneWidget,
    );
    expect(find.text('Create member'), findsOneWidget);
  });
  testWidgets(
    'changing gym while details open never fetches old member in new gym',
    (tester) async {
      final repository = FakeMemberRepository();
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(
        find.text('The gym context changed. Return to Members to continue.'),
        findsOneWidget,
      );
      expect(repository.operations.any((op) => op.contains(gymB)), isFalse);
    },
  );
  testWidgets('trainer member deep links cannot enter admin UI', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    final container = await pumpMembers(
      tester,
      repository,
      role: AuthRole.trainer,
    );
    container
        .read(appRouterProvider)
        .go('${AppRoutes.members}/$memberId?gymId=$gymA');
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(repository.listCalls, isEmpty);
    expect(repository.operations, isEmpty);
  });
  testWidgets(
    'successful refresh hides protected content and retains the member form',
    (tester) async {
      final repository = FakeMemberRepository();
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await openForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Retained',
      );
      final api = container.read(authApiServiceProvider) as FakeAuthApi;
      api.refreshGate = Completer<void>();
      final recovery = container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restoring your session…'), findsOneWidget);
      expect(find.byKey(const ValueKey('firstName')), findsNothing);
      api.refreshGate!.complete();
      await recovery;
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        '${AppRoutes.members}/new',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('firstName')))
            .controller!
            .text,
        'Retained',
      );
      expect(repository.listCalls.length, 1);
    },
  );
  testWidgets('failed recovery discards protected member pages', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    final container = await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex River'));
    await tester.pumpAndSettle();
    final api = container.read(authApiServiceProvider) as FakeAuthApi;
    api.refreshFailure = const AuthFailure(AuthFailureKind.invalidSession);
    await expectLater(
      container.read(sessionControllerProvider.notifier).refreshSession(),
      throwsA(isA<AuthFailure>()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Member details'), findsNothing);
    container
        .read(appRouterProvider)
        .go('${AppRoutes.members}/$memberId?gymId=$gymA');
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
  });
  testWidgets(
    'logout from member details returns to login and clears protected data',
    (tester) async {
      final repository = FakeMemberRepository();
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(await container.read(membersProvider.future), isNull);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );
  testWidgets(
    'unauthenticated member deep link redirects before any API call',
    (tester) async {
      final repository = FakeMemberRepository();
      final container = await pumpMembers(
        tester,
        repository,
        authenticated: false,
      );
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$memberId?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(repository.listCalls, isEmpty);
      expect(repository.operations, isEmpty);
    },
  );
  testWidgets('member list fits 320px screen with larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMembers(tester, FakeMemberRepository());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
