import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
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
import 'package:gym_management_app/features/members/providers/member_overview_providers.dart';
import 'package:gym_management_app/features/members/models/member_overview.dart';
import 'package:gym_management_app/features/members/presentation/member_form_page.dart';
import 'package:gym_management_app/features/members/presentation/member_details_page.dart';
import 'package:gym_management_app/features/members/presentation/members_page.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';

void main() {
  late FakeMemberOverviewRepository overview;
  Future<ProviderContainer> pumpMembers(
    WidgetTester tester,
    FakeMemberRepository repository, {
    AuthRole role = AuthRole.admin,
    bool authenticated = true,
    List<Map<String, dynamic>>? rows,
  }) async {
    overview = FakeMemberOverviewRepository(repository, rows: rows);
    final api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    final container = ProviderContainer(
      overrides: [
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        ),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(repository),
        memberOverviewRepositoryProvider.overrideWithValue(overview),
        memberOnboardingRepositoryProvider.overrideWithValue(
          FakeOnboardingRepository()
            ..failure = StateError('No fresh submission'),
        ),
        pendingOnboardingStoreProvider.overrideWithValue(
          SecurePendingOnboardingStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GymApp(animateDecorations: false),
      ),
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
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    if (finder.evaluate().isEmpty) {
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200, scrollable: scroll);
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('Add member').first);
    await tester.pumpAndSettle();
  }

  // Preserve legacy standalone form coverage independently of the new wizard route.
  Future<void> openStandaloneCreate(WidgetTester tester) async {
    Navigator.of(
      tester.element(find.byType(MembersPageView)),
      rootNavigator: true,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: SafeArea(child: MemberFormPage(gymId: gymA)),
        ),
      ),
    );
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

  testWidgets('opening and cancelling birth-date picker keeps edit clean', (
    tester,
  ) async {
    final repository = _DatedMembers();
    final scope = await pumpMembers(tester, repository);
    scope
        .read(appRouterProvider)
        .go('${AppRoutes.members}/$memberId/edit?gymId=$gymA');
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('dateOfBirth')));
    expect(find.text('Jan 2, 2000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dateOfBirth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Back to Members'));
    await tester.tap(find.byTooltip('Back to Members'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(repository.writes, isEmpty);
  });
  testWidgets(
    'clearing a birth date marks edit dirty and saves only a member PATCH',
    (tester) async {
      final repository = _DatedMembers();
      final scope = await pumpMembers(tester, repository);
      scope
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$memberId/edit?gymId=$gymA');
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('Clear date of birth'));
      await tester.tap(find.byTooltip('Clear date of birth'));
      await reveal(tester, find.byTooltip('Back to Members'));
      await tester.tap(find.byTooltip('Back to Members'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repository.writes, hasLength(1));
      expect(repository.writes.single.containsKey('dateOfBirth'), true);
      expect(repository.writes.single['dateOfBirth'], isNull);
      expect(
        repository.operations.where((op) => op.startsWith('update:')),
        hasLength(1),
      );
      expect(
        repository.operations.where((op) => op.startsWith('onboard:')),
        isEmpty,
      );
    },
  );

  testWidgets('saving member edit blocks route exits and gym switching', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    final scope = await pumpMembers(tester, repository);
    scope
        .read(appRouterProvider)
        .go('${AppRoutes.members}/$memberId/edit?gymId=$gymA');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('firstName')), 'Edited');
    repository.saveGate = Completer<MemberProfile>();
    await reveal(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(0);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '${AppRoutes.members}/$memberId/edit',
    );
    await tester.tap(find.byTooltip('Admin navigation'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your workspace'), findsNothing);
    expect(
      scope.read(appRouterProvider).state.uri.path,
      '${AppRoutes.members}/$memberId/edit',
    );
    expect(repository.writes, hasLength(1));
    expect(find.text('Discard unsaved changes?'), findsNothing);
    repository.saveGate!.complete(
      MemberProfile.fromJson(profileJson(firstName: 'Edited')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MemberFormPage), findsNothing);
    expect(find.text('Discard unsaved changes?'), findsNothing);
  });

  for (final exit in [
    'system',
    'app Back',
    'tab',
    'drawer',
    'account drawer',
  ]) {
    testWidgets('member edit $exit protects actual edits and can discard', (
      tester,
    ) async {
      final repository = FakeMemberRepository();
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Edit member'));
      await tester.tap(find.text('Edit member'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('firstName')), 'Edited');
      await tester.pumpAndSettle();
      Future<void> leave() async {
        switch (exit) {
          case 'system':
            await tester.binding.handlePopRoute();
          case 'app Back':
            await tester.tap(find.byTooltip('Back to Members'));
          case 'tab':
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text('Dashboard'),
              ),
            );
          case 'drawer':
          case 'account drawer':
            await tester.tap(find.byTooltip('Admin navigation'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(Drawer),
                matching: find.text(
                  exit == 'account drawer' ? 'More' : 'Dashboard',
                ),
              ),
            );
        }
        await tester.pumpAndSettle();
      }

      await leave();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      await leave();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberFormPage), findsNothing);
      expect(repository.writes, isEmpty);
    });
  }

  testWidgets('unchanged edit and reverted edit leave without warning', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    final scope = await pumpMembers(tester, repository);
    for (final reverted in [false, true]) {
      scope
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$memberId/edit?gymId=$gymA');
      await tester.pumpAndSettle();
      if (reverted) {
        await tester.enterText(
          find.byKey(const ValueKey('firstName')),
          'Edited',
        );
        await tester.enterText(find.byKey(const ValueKey('firstName')), 'Alex');
      }
      await tester.tap(find.byTooltip('Back to Members'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsNothing);
      expect(find.byType(MemberFormPage), findsNothing);
    }
    expect(repository.writes, isEmpty);
  });

  testWidgets('member list renders overview rows and server pagination', (
    tester,
  ) async {
    final repository = FakeMemberRepository()..total = 21;
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Alex River'), findsOneWidget);
    expect(find.text('Monthly · 20 days left'), findsOneWidget);
    expect(find.text('Paid in full'), findsOneWidget);
    expect(find.byTooltip('Call Alex'), findsOneWidget);
    expect(find.byTooltip('WhatsApp Alex'), findsOneWidget);
    expect(repository.listCalls, isEmpty, reason: 'no per-member list reads');
    await reveal(tester, find.text('Page 1 · 21 total'));
    await reveal(tester, find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.page, 2);
    await reveal(tester, find.text('Page 2 · 21 total'));
    await reveal(tester, find.byTooltip('Previous page'));
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.page, 1);
  });
  testWidgets('Add member opens the existing wizard', (tester) async {
    final scope = await pumpMembers(tester, FakeMemberRepository());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add member').first);
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).state.uri.path,
      '${AppRoutes.members}/new',
    );
    expect(find.byKey(const ValueKey('onboarding-step-title')), findsOneWidget);
  });
  testWidgets('filter chips query the server and reset to page one', (
    tester,
  ) async {
    final repository = FakeMemberRepository()..total = 21;
    final container = await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.page, 2);
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Expiring 0'));
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.filter, MemberOverviewFilter.expiring);
    expect(overview.calls.last.query.page, 1);
    expect(
      container.read(memberOverviewQueryProvider).filter,
      MemberOverviewFilter.expiring,
    );
    expect(find.text('1 expiring in the next 7 days'), findsNothing);
  });
  testWidgets('expired member shows renewal action and opens details', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    await pumpMembers(
      tester,
      repository,
      rows: [FakeMemberOverviewRepository.row(gymId: gymA, state: 'expired')],
    );
    await tester.pumpAndSettle();
    expect(find.text('Monthly · Expired 3 days ago'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Renew'), findsOneWidget);
    await tester.tap(find.text('Alex River'));
    await tester.pumpAndSettle();
    expect(find.text('Member details'), findsOneWidget);
    final details = tester.widget<MemberDetailsPage>(
      find.byType(MemberDetailsPage),
    );
    expect(details.memberId, memberId);
    expect(details.gymId, gymA);
    expect(repository.writes, isEmpty);
  });
  testWidgets('dues row offers Collect for the unpaid membership', (
    tester,
  ) async {
    final container = await pumpMembers(
      tester,
      FakeMemberRepository(),
      rows: [
        FakeMemberOverviewRepository.row(gymId: gymA, balancePaise: 150000),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Collect ₹1,500'));
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).state.uri.path,
      '${AppRoutes.members}/$memberId/membership/subscription-1',
    );
  });
  testWidgets('empty gym invites the first member', (tester) async {
    final container = await pumpMembers(
      tester,
      FakeMemberRepository()..empty = true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Add your first member'), findsOneWidget);
    await reveal(tester, find.widgetWithText(FilledButton, 'Add member').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Add member').last);
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).state.uri.path,
      '${AppRoutes.members}/new',
    );
  });
  testWidgets('loading indicator while list request is pending', (
    tester,
  ) async {
    final repository = FakeMemberRepository()..delayLists = true;
    await pumpMembers(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.delayLists = false;
    repository.empty = true;
    overview.pending.single.complete(
      await overview.list(gymA, const MemberOverviewQuery()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add your first member'), findsOneWidget);
  });
  testWidgets('safe error retry and pull refresh', (tester) async {
    final repository = FakeMemberRepository()
      ..failure = const MemberFailure('Connection unavailable');
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Connection unavailable'), findsOneWidget);
    repository.failure = null;
    await reveal(tester, find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    final afterRetry = overview.calls.length;
    expect(find.text('Alex River'), findsOneWidget);
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Members').first, const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(overview.calls.length, greaterThan(afterRetry));
  });
  testWidgets('search trims text, keeps the filter and resets pagination', (
    tester,
  ) async {
    final container = await pumpMembers(tester, FakeMemberRepository());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dues 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Alex ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.search, 'Alex');
    expect(overview.calls.last.query.filter, MemberOverviewFilter.dues);
    expect(overview.calls.last.query.page, 1);
    expect(container.read(memberOverviewQueryProvider).search, 'Alex');
  });
  testWidgets('no matches offers to show all members', (tester) async {
    final repository = FakeMemberRepository();
    await pumpMembers(
      tester,
      repository,
      rows: [FakeMemberOverviewRepository.row(gymId: gymA)],
    );
    await tester.pumpAndSettle();
    overview.rows = [];
    await tester.enterText(find.byType(TextField), 'Not found');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('No members match “Not found”.'), findsOneWidget);
    overview.rows = [FakeMemberOverviewRepository.row(gymId: gymA)];
    await reveal(tester, find.text('Show all members'));
    await tester.tap(find.text('Show all members'));
    await tester.pumpAndSettle();
    expect(overview.calls.last.query.search, isEmpty);
    expect(overview.calls.last.query.filter, MemberOverviewFilter.all);
    expect(find.text('Alex River'), findsOneWidget);
  });
  testWidgets('members fits a narrow phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMembers(
      tester,
      FakeMemberRepository(),
      rows: [
        FakeMemberOverviewRepository.row(gymId: gymA, balancePaise: 9999900),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add member'), findsOneWidget);
    await reveal(tester, find.text('Alex River'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'details summary, membership history, cancellation details and back',
    (tester) async {
      final repository = FakeMemberRepository()..populated = true;
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(find.text('Member details'), findsOneWidget);
      await reveal(tester, find.text('Assigned trainers'));
      await tester.tap(find.text('Assigned trainers'));
      await tester.pumpAndSettle();
      expect(find.text('Central (active)'), findsNothing);
      expect(
        repository.operations.where((op) => op.startsWith('get:')),
        isEmpty,
      );
      await reveal(tester, find.textContaining('Total paid'));
      expect(find.textContaining('Total paid'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('member-payments-row')),
          matching: find.textContaining('₹3.03'),
        ),
        findsOneWidget,
      );
      await reveal(tester, find.textContaining('Pat Lee'));
      expect(find.textContaining('Pat Lee'), findsOneWidget);
      // History starts collapsed.
      await reveal(tester, find.text('Membership history'));
      await tester.tap(find.text('Membership history'));
      await tester.pumpAndSettle();
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
      await openStandaloneCreate(tester);
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
      expect(overview.calls.length, 2, reason: 'the list refreshes once');
      expect(find.text('Add member'), findsOneWidget);
    },
  );
  testWidgets(
    'edit loads server profile and prevents immutable identity changes',
    (tester) async {
      final repository = FakeMemberRepository();
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Edit member'));
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
      expect(find.byType(MemberDetailsPage), findsOneWidget);
      // The taller identity header can scroll out of the lazy list after Edit.
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(MemberDetailsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Member details'), findsOneWidget);
    },
  );
  testWidgets('server duplicate validation remains in form for correction', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await openStandaloneCreate(tester);
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
      await reveal(tester, find.text('Alex River'));
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
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('firstName')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Retained',
      );
      expect(overview.calls.length, 1, reason: 'no reload after recovery');
    },
  );
  testWidgets('failed recovery discards protected member pages', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    final container = await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Alex River'));
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
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Admin navigation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Logout'));
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

class _DatedMembers extends FakeMemberRepository {
  @override
  Future<MemberProfile> get(String gymId, String id) async =>
      MemberProfile.fromJson({
        ...profileJson(gymId: gymId),
        'dateOfBirth': '2000-01-02',
      });
}
