import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'package:gym_management_app/shared/widgets/membership_date_range.dart';
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
import 'package:gym_management_app/features/members/presentation/member_form_page.dart';
import 'package:gym_management_app/features/members/presentation/member_details_page.dart';
import 'package:gym_management_app/features/members/presentation/member_details_financial_cards.dart';
import 'package:gym_management_app/features/members/presentation/members_page.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';

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
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add member'));
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

  testWidgets('minimal member list renders names and server pagination', (
    tester,
  ) async {
    final repository = FakeMemberRepository()..total = 21;
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Alex River'), findsOneWidget);
    expect(find.textContaining('ME01 · +91 9876543210'), findsNothing);
    expect(find.byTooltip('Add member'), findsOneWidget);
    await reveal(tester, find.text('Page 1 · 21 total'));
    expect(find.text('Page 1 · 21 total'), findsOneWidget);
    await reveal(tester, find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.page, 2);
    await reveal(tester, find.text('Page 2 · 21 total'));
    expect(find.text('Page 2 · 21 total'), findsOneWidget);
    await reveal(tester, find.byTooltip('Previous page'));
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.page, 1);
  });
  testWidgets(
    'icon-only Add member is accessible and opens the existing wizard',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final scope = await pumpMembers(tester, FakeMemberRepository());
      await tester.pumpAndSettle();
      expect(find.text('Add member'), findsNothing);
      expect(find.byTooltip('Add member'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byTooltip('Add member'))
            .getSemanticsData()
            .tooltip,
        'Add member',
      );
      final button = find
          .ancestor(
            of: find.byTooltip('Add member'),
            matching: find.byType(IconButton),
          )
          .first;
      expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).state.uri.path,
        '${AppRoutes.members}/new',
      );
      expect(
        find.byKey(const ValueKey('onboarding-step-title')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
  testWidgets(
    'gender-only menu paginates matches and All restores other genders',
    (tester) async {
      final repository = GenderMemberRepository();
      final scope = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filter by gender'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Male'),
      );
      await tester.pumpAndSettle();
      expect(scope.read(membersProvider).asData!.value!.pagination.total, 42);
      expect(
        scope
            .read(membersProvider)
            .asData!
            .value!
            .members
            .every((member) => member.gender == 'male'),
        true,
      );
      await reveal(tester, find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(scope.read(memberQueryProvider).page, 2);
      expect(scope.read(memberQueryProvider).gender, 'male');
      final scroll = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filter by gender'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Female'),
      );
      await tester.pumpAndSettle();
      expect(scope.read(memberQueryProvider).page, 1);
      expect(
        scope
            .read(membersProvider)
            .asData!
            .value!
            .members
            .every((member) => member.gender == 'female'),
        true,
      );
      await tester.tap(find.byTooltip('Filter by gender'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'All'),
      );
      await tester.pumpAndSettle();
      expect(scope.read(memberQueryProvider).gender, isNull);
      expect(scope.read(membersProvider).asData!.value!.pagination.total, 125);
      expect(
        scope
            .read(membersProvider)
            .asData!
            .value!
            .members
            .any((member) => member.gender == null),
        true,
      );
    },
  );
  testWidgets(
    'expired card reads verified complete history balance and opens member details',
    (tester) async {
      final repository = _ExpiredMembers();
      await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      expect(
        repository.operations.where((operation) => operation == 'history:1'),
        hasLength(1),
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Expired previous membership')),
        findsOneWidget,
      );
      expect(find.text('₹500.00 due'), findsOneWidget);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '1 Mar 2026 – 31 Mar 2026',
      );
      expect(find.text('1 Mar 2026 – 31 Mar 2026'), findsOneWidget);
      expect(find.text('Fully Paid'), findsNothing);
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(find.text('Member details'), findsOneWidget);
      final details = tester.widget<MemberDetailsPage>(
        find.byType(MemberDetailsPage),
      );
      expect(details.memberId, memberId);
      expect(details.gymId, gymA);
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('empty list is actionable', (tester) async {
    await pumpMembers(tester, FakeMemberRepository()..empty = true);
    await tester.pumpAndSettle();
    expect(find.text('No members yet. Add your first member.'), findsOneWidget);
    expect(find.byTooltip('Add member'), findsOneWidget);
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
    await reveal(tester, find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 2);
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
    expect(repository.listCalls.length, 3);
  });
  testWidgets(
    'search and gender-only menu preserve search and reset pagination',
    (tester) async {
      final repository = FakeMemberRepository();
      final container = await pumpMembers(tester, repository);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' Alex ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.search, 'Alex');
      await tester.tap(find.byTooltip('Filter by gender'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(3));
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Inactive'), findsNothing);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Male'),
      );
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.status, isNull);
      expect(repository.listCalls.last.query.search, 'Alex');
      expect(container.read(memberQueryProvider).gender, 'male');
      expect(repository.listCalls.last.query.page, 1);
    },
  );
  testWidgets('filtered empty state clears the actual server filters', (
    tester,
  ) async {
    final repository = FakeMemberRepository();
    await pumpMembers(tester, repository);
    await tester.pumpAndSettle();
    repository.empty = true;
    await tester.enterText(find.byType(TextField), 'Not found');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Clear filters'));
    expect(find.text('No matching members'), findsOneWidget);
    repository.empty = false;
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.search, isEmpty);
    expect(repository.listCalls.last.query.status, isNull);
    expect(repository.listCalls.last.query.page, 1);
    expect(find.text('Alex River'), findsOneWidget);
  });
  testWidgets('first-member empty action uses the existing create route', (
    tester,
  ) async {
    final container = await pumpMembers(
      tester,
      FakeMemberRepository()..empty = true,
    );
    await reveal(tester, find.text('Create your first member'));
    await tester.tap(find.text('Create your first member'));
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).state.uri.path,
      '${AppRoutes.members}/new',
    );
    expect(find.byKey(const ValueKey('onboarding-step-title')), findsOneWidget);
  });
  testWidgets('members fits a narrow phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMembers(tester, FakeMemberRepository());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add member'), findsOneWidget);
    await reveal(tester, find.text('Alex River'));
    expect(find.text('No membership'), findsOneWidget);
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
      await reveal(tester, find.text('Central (active)'));
      expect(find.text('Central (active)'), findsOneWidget);
      expect(
        repository.operations.where((op) => op.startsWith('get:')),
        isEmpty,
      );
      await reveal(tester, find.text('Total paid'));
      expect(find.text('Total paid'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MemberPaymentSummaryCard),
          matching: find.text('₹3.03'),
        ),
        findsOneWidget,
      );
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
      expect(repository.listCalls.length, 2);
      expect(find.byTooltip('Add member'), findsOneWidget);
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
      expect(repository.listCalls.length, 1);
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

class _ExpiredMembers extends FakeMemberRepository {
  @override
  Future<MembershipHistory> memberships(
    String gymId,
    String id,
    int page,
  ) async {
    operations.add('history:$page');
    return MembershipHistory.fromResponse(
      {
        'member': {'id': id},
        'currentMembership': null,
        'subscriptions': [
          subscriptionJson()..addAll({
            'status': 'expired',
            'isCurrentlyActive': false,
            'paymentSummary': {
              'totalSuccessfulPaidPaise': 100000,
              'remainingBalancePaise': 50000,
            },
          }),
        ],
      },
      {'page': page, 'limit': 20, 'total': 1},
    );
  }

  @override
  Future<MemberSummary> summary(String gymId, String id) async {
    final json = summaryJson(populated: true);
    json['currentSubscription'] = null;
    json['currentSubscriptionPaymentSummary'] = null;
    json['subscriptionHistory'] = {
      'items': [
        subscriptionJson()
          ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
      ],
      'page': 1,
      'limit': 20,
      'total': 1,
    };
    return MemberSummary.fromJson(json);
  }

  @override
  Future<MembershipDetail> membership(
    String gymId,
    String id,
    String subId,
  ) async {
    operations.add('membership:$gymId:$id:$subId');
    return MembershipDetail.fromJson({
      'subscription': subscriptionJson()
        ..addAll({'status': 'expired', 'isCurrentlyActive': false}),
      'paymentSummary': {
        'totalSuccessfulPaidPaise': 100000,
        'remainingBalancePaise': 50000,
      },
    });
  }
}
