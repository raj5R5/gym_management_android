import 'package:gym_management_app/features/owner_profile/owner_profile.dart';
import 'package:gym_management_app/features/leads/leads.dart';
import 'package:gym_management_app/features/members/birthdays.dart';
import '../leads/lead_fakes.dart';
import 'package:gym_management_app/features/adjustments/adjustments.dart';
import 'package:gym_management_app/features/adjustments/adjustment_widgets.dart';
import '../money/adjustment_fakes.dart';
import 'package:gym_management_app/features/expenses/expenses.dart';
import '../money/expense_fakes.dart';
import 'package:gym_management_app/features/gym_settings/gym_settings_page.dart';
import 'package:gym_management_app/features/visits/visit_repository.dart';
import '../visits/visit_fakes.dart';
import 'package:gym_management_app/features/members/models/member_overview.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/dashboard_widgets.dart';
import 'package:gym_management_app/features/members/providers/member_overview_providers.dart';
import 'package:gym_management_app/features/gym_settings/gym_settings.dart';
import '../gym_settings/gym_settings_fakes.dart';
import 'package:gym_management_app/features/owner_profile/owner_signup_photo.dart';
import '../owner_profile/owner_profile_widgets_test.dart'
    show ProfilesFake, NoSignupPhoto;
import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import '../members/photo_fakes.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/circular_metric_card.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/dashboard_date_range_dialog.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/trainers/providers/trainer_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import '../auth/auth_fakes.dart';
import '../members/member_fakes.dart';
import '../members/onboarding_fakes.dart';
import '../memberships/billing_fakes.dart';
import '../trainers/trainer_fakes.dart';
import 'dashboard_fakes.dart';

void main() {
  Future<ProviderContainer> pumpAdmin(
    WidgetTester tester,
    FakeDashboardRepository repository, {
    AuthRole role = AuthRole.admin,
    bool authenticated = true,
    List<String> gyms = const [gymA],
    bool onboarding = false,
    bool ownerProfile = false,
    FakeMembershipRepository? plans,
    FakeGymSettingsRepository? settings,
    List<Map<String, dynamic>>? overviewRows,
    FakeVisitRepository? visits,
    FakeExpenseRepository? expenses,
    FakeAdjustmentRepository? adjustments,
    FakeLeadRepository? leads,
    List<UpcomingBirthday> birthdays = const [],
  }) async {
    final members = FakeMemberRepository()..empty = overviewRows == null;
    final api = FakeAuthApi()..identity = adminIdentity(gyms: gyms, role: role);
    final scope = ProviderContainer(
      overrides: [
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(
            apiBaseUrl: onboarding || ownerProfile ? onboardingUrl : '',
          ),
        ),
        if (onboarding) ...[
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
        if (ownerProfile) ...[
          ownerProfileRepositoryProvider.overrideWithValue(ProfilesFake()),
          ownerSignupPhotoStoreProvider.overrideWithValue(NoSignupPhoto()),
        ],
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(repository),
        trainerRepositoryProvider.overrideWithValue(
          FakeTrainerRepository()..empty = true,
        ),
        memberRepositoryProvider.overrideWithValue(members),
        memberOverviewRepositoryProvider.overrideWithValue(
          FakeMemberOverviewRepository(members, rows: overviewRows),
        ),
        gymSettingsRepositoryProvider.overrideWithValue(
          settings ?? FakeGymSettingsRepository(),
        ),
        visitRepositoryProvider.overrideWithValue(
          visits ?? FakeVisitRepository(),
        ),
        expenseRepositoryProvider.overrideWithValue(
          expenses ?? FakeExpenseRepository(),
        ),
        adjustmentRepositoryProvider.overrideWithValue(
          adjustments ?? FakeAdjustmentRepository(),
        ),
        leadRepositoryProvider.overrideWithValue(
          leads ?? FakeLeadRepository(leads: []),
        ),
        upcomingBirthdaysProvider.overrideWith((ref) async => birthdays),
        membershipRepositoryProvider.overrideWithValue(
          plans ?? FakeMembershipRepository(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const GymApp(animateDecorations: false),
      ),
    );
    await tester.pump();
    return scope;
  }

  testWidgets(
    'owner profile retains unsaved fields across access-token refresh',
    (tester) async {
      final scope = await pumpAdmin(
        tester,
        FakeDashboardRepository(),
        ownerProfile: true,
      );
      await tester.pumpAndSettle();
      scope.read(appRouterProvider).go(AppRoutes.ownerProfile);
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('profile-displayName'));
      await tester.enterText(name, 'Unsaved owner');
      await tester.pump();
      final api = scope.read(authApiServiceProvider) as FakeAuthApi;
      api.refreshGate = Completer<void>();
      final recovery = scope
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restoring your session…'), findsOneWidget);
      expect(
        scope.read(appRouterProvider).state.uri.path,
        AppRoutes.ownerProfile,
      );
      api.refreshGate!.complete();
      await recovery;
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).state.uri.path,
        AppRoutes.ownerProfile,
      );
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Unsaved owner',
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }

  Future<void> scrollToTop(WidgetTester tester) async {
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
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
      expect(find.text('Whole gym · All branches'), findsNothing);
      expect(find.text('Current gym'), findsOneWidget);
      expect(find.text('Welcome back, Admin'), findsNothing);
      expect(find.text('Your gym, at a glance.'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('1 Mar 2026 · Inclusive'), findsNothing);
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('dashboard-period')))
            .properties
            .label,
        contains('1 Mar 2026'),
      );
      expect(find.text('Gym timezone: Asia/Kolkata'), findsNothing);
      expect(repository.requests.single.gymId, gymA);
      await tester.scrollUntilVisible(find.text('Money collected'), 250);
      expect(find.text('₹12,34,567.89'), findsOneWidget);
      await reveal(tester, find.text('Active Plans'));
      expect(find.byType(CircularMetricCard), findsNWidgets(4));
      expect(find.byType(MetricRing), findsNWidgets(4));
      final cards = tester
          .widgetList<CircularMetricCard>(find.byType(CircularMetricCard))
          .toList();
      expect(cards.map((card) => card.color), [
        AppPalette.ember,
        PendingColors.accent,
        AppPalette.ember,
        AppPalette.ember,
      ]);
      expect(cards.first.layout, MetricCardLayout.revenueHero);
      expect(
        tester
            .widget<MetricRing>(
              find.descendant(
                of: find.byWidget(cards.first),
                matching: find.byType(MetricRing),
              ),
            )
            .color,
        AppPalette.ember,
      );
      expect(cards[1].surfaceTint, PendingColors.surface);
      expect(cards[1].iconBackground, PendingColors.surface);
      final pendingRing = tester.widget<MetricRing>(
        find.descendant(
          of: find.byWidget(cards[1]),
          matching: find.byType(MetricRing),
        ),
      );
      expect(pendingRing.color, PendingColors.accent);
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byWidget(cards[1]),
                matching: find.byIcon(Icons.account_balance_wallet_outlined),
              ),
            )
            .color,
        PendingColors.accent,
      );
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
      await pumpAdmin(
        tester,
        repository,
        plans: FakeMembershipRepository()..empty = true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Loading your gym overview…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repository.gate!.complete(
        GymDashboard.fromJson(dashboardJson(empty: true)),
      );
      await tester.pumpAndSettle();
      // A brand-new gym gets a setup checklist instead of a zero-state panel.
      await reveal(tester, find.text('Finish setting up'));
      expect(find.text('2 of 5 done'), findsOneWidget);
      expect(find.text('Create a membership plan'), findsOneWidget);
      expect(find.text('Add your first member'), findsOneWidget);
      await scrollToTop(tester);
      await tester.scrollUntilVisible(find.text('Money collected'), 250);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Money collected'),
            matching: find.byType(CircularMetricCard),
          ),
          matching: find.text('₹0.00'),
        ),
        findsOneWidget,
      );
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
    await reveal(tester, find.text('Retry dashboard'));
    await tester.tap(find.text('Retry dashboard'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 2);
    await scrollToTop(tester);
    await tester.tap(find.byTooltip('Refresh dashboard'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 3);
  });
  testWidgets(
    'outstanding dues are separate from revenue and refresh from saved metrics',
    (tester) async {
      final repository = FakeDashboardRepository()
        ..result = GymDashboard.fromJson(
          dashboardJson(revenue: 100000, outstanding: 50000),
        );
      final plans = FakeMembershipRepository()..total = 2;
      final scope = await pumpAdmin(
        tester,
        repository,
        gyms: [gymA, gymB],
        plans: plans,
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('₹1,000.00'), findsOneWidget);
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹500.00'), findsOneWidget);
      expect(
        tester
            .widget<CircularMetricCard>(
              find.ancestor(
                of: find.text('Pending dues'),
                matching: find.byType(CircularMetricCard),
              ),
            )
            .caption,
        'Current membership dues',
      );
      repository.result = GymDashboard.fromJson(
        dashboardJson(revenue: 125000, outstanding: 25000),
      );
      plans.total = 4;
      await scrollToTop(tester);
      await tester.tap(find.byTooltip('Refresh dashboard'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹250.00'), findsOneWidget);
      expect(find.text('₹500.00'), findsNothing);
      repository.result = GymDashboard.fromJson(
        dashboardJson(revenue: 0, outstanding: 75000),
      );
      scope.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹750.00'), findsOneWidget);
      expect(repository.requests.last.gymId, gymB);
    },
  );

  testWidgets(
    'gym-local today stays zero while historical selection shows its successful revenue',
    (tester) async {
      Map<String, dynamic> response(String day, int revenue, int payments) {
        final json = dashboardJson(revenue: revenue, outstanding: 50000);
        json['period'] = {
          'timezone': 'Asia/Kolkata',
          'from': '2026-10-$day',
          'to': '2026-10-$day',
          'startUtc': day == '12'
              ? '2026-10-11T18:30:00.000Z'
              : '2026-10-09T18:30:00.000Z',
          'endUtc': day == '12'
              ? '2026-10-12T18:30:00.000Z'
              : '2026-10-10T18:30:00.000Z',
          'branchId': null,
        };
        (json['payments'] as Map)['periodSuccessfulCount'] = payments;
        return json;
      }

      final repository = FakeDashboardRepository()
        ..result = GymDashboard.fromJson(response('12', 0, 0));
      final scope = await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('TODAY · 12 OCT 2026'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('No payments during this period'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      repository.result = GymDashboard.fromJson(response('10', 100000, 1));
      scope
          .read(dashboardQueryProvider.notifier)
          .selectRange(CalendarDate(2026, 10, 10), CalendarDate(2026, 10, 10));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('10 OCT 2026'), findsOneWidget);
      expect(find.text('₹1,000.00'), findsOneWidget);
      expect(find.text('No payments during this period'), findsNothing);
      expect(find.text('₹500.00'), findsOneWidget);
      expect(repository.requests.last.query.toParameters(), {
        'from': '2026-10-10',
        'to': '2026-10-10',
      });
      repository.result = GymDashboard.fromJson(response('12', 0, 0));
      scope.read(dashboardQueryProvider.notifier).useGymToday();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('TODAY · 12 OCT 2026'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('₹1,000.00'), findsNothing);
      expect(find.text('No payments during this period'), findsOneWidget);
      expect(repository.requests.last.query.toParameters(), isEmpty);
    },
  );

  testWidgets(
    'quick filters are server presets; repeated selected tap makes no duplicate call',
    (tester) async {
      final repository = FakeDashboardRepository();
      final scope = await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      final sevenDays = dashboardJson();
      (sevenDays['period'] as Map)
        ..['to'] = '2026-03-07'
        ..['endUtc'] = '2026-03-07T18:30:00.000Z';
      repository.result = GymDashboard.fromJson(sevenDays);
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.toParameters(), {
        'preset': 'last7Days',
      });
      expect(
        scope.read(dashboardQueryProvider).filter,
        DashboardDateFilter.last7Days,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '7 days'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('dashboard-period')))
            .properties
            .label,
        contains('1 Mar 2026 – 7 Mar 2026'),
      );
      expect(find.text('1 Mar 2026 – 7 Mar 2026 · Inclusive'), findsNothing);
      final requests = repository.requests.length;
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(repository.requests.length, requests);
      final month = dashboardJson();
      (month['period'] as Map)
        ..['to'] = '2026-03-31'
        ..['endUtc'] = '2026-03-31T18:30:00.000Z';
      repository.result = GymDashboard.fromJson(month);
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.toParameters(), {
        'preset': 'thisMonth',
      });
      expect(find.text('THIS MONTH · MARCH 2026'), findsOneWidget);
      repository.result = GymDashboard.fromJson(dashboardJson());
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.toParameters(), isEmpty);
      await tester.tap(find.text('Custom range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        scope.read(dashboardQueryProvider).filter,
        DashboardDateFilter.today,
      );
      expect(repository.requests.length, requests + 2);
    },
  );

  testWidgets(
    'failed refresh keeps same-scope values; a gym change clears the old display',
    (tester) async {
      final repository = FakeDashboardRepository();
      final scope = await pumpAdmin(tester, repository, gyms: [gymA, gymB]);
      await tester.pumpAndSettle();
      repository.gate = Completer<GymDashboard>();
      await tester.tap(find.byTooltip('Refresh dashboard'));
      await tester.pump();
      expect(find.text('Updating your gym overview…'), findsOneWidget);
      expect(find.text('₹12,34,567.89'), findsOneWidget);
      repository.gate!.completeError(
        const AuthFailure(AuthFailureKind.network),
      );
      repository.gate = null;
      await tester.pumpAndSettle();
      expect(
        find.text('Refresh failed · Showing last successful data'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Money collected'));
      expect(find.text('₹12,34,567.89'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      repository.gate = Completer<GymDashboard>();
      scope.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pump();
      expect(find.text('₹12,34,567.89'), findsNothing);
      repository.gate!.complete(
        GymDashboard.fromJson(dashboardJson(empty: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('₹12,34,567.89'), findsNothing);
    },
  );

  testWidgets(
    'access denial clears retained metrics instead of presenting stale authorized data',
    (tester) async {
      final repository = FakeDashboardRepository();
      await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('₹12,34,567.89'), findsOneWidget);
      repository.failure = const AuthFailure(AuthFailureKind.forbidden);
      await tester.tap(find.byTooltip('Refresh dashboard'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('₹12,34,567.89'), findsNothing);
      expect(find.text('₹500.00'), findsNothing);
      expect(
        find.text('Refresh failed · Showing last successful data'),
        findsNothing,
      );
      await scrollToTop(tester);
      expect(find.text('This action is not permitted.'), findsOneWidget);
    },
  );
  testWidgets('member/trainer sections, back to dashboard, more/logout', (
    tester,
  ) async {
    final scope = await pumpAdmin(tester, FakeDashboardRepository());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members').last);
    await tester.pumpAndSettle();
    expect(find.text('Add your first member'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
    await tester.tap(find.text('Trainers').last);
    await tester.pumpAndSettle();
    expect(
      find.text('No trainers yet. Add your first trainer.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Admin navigation'));
    await tester.pumpAndSettle();
    // The drawer lists more pages than fit the test screen.
    await tester.dragUntilVisible(
      find.widgetWithText(ListTile, 'More'),
      find.byType(Drawer),
      const Offset(0, -200),
    );
    // Bring it fully on screen: a tile at the very edge misses the tap.
    await tester.drag(find.byType(Drawer), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.ensureVisible(find.text('Logout'));
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
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
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardDateRangeDialog), findsOneWidget);
    expect(find.text('Both dates included · Up to 366 days'), findsOneWidget);
  });
  testWidgets('date selection and gym-local today preserve request semantics', (
    tester,
  ) async {
    final repository = FakeDashboardRepository();
    final scope = await pumpAdmin(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-03-01')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-03-07')));
    await tester.pump();
    final json = dashboardJson();
    (json['period'] as Map<String, dynamic>)
      ..['to'] = '2026-03-07'
      ..['endUtc'] = '2026-03-07T18:30:00.000Z';
    repository.result = GymDashboard.fromJson(json);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 2);
    expect(repository.requests.last.query.toParameters(), {
      'from': '2026-03-01',
      'to': '2026-03-07',
    });
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('dashboard-period')))
          .properties
          .label,
      contains('1 Mar 2026 – 7 Mar 2026'),
    );
    expect(find.text('1 Mar 2026 – 7 Mar 2026 · Inclusive'), findsNothing);
    repository.result = GymDashboard.fromJson(dashboardJson());
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 3);
    expect(repository.requests.last.query.toParameters(), isEmpty);
    expect(scope.read(dashboardQueryProvider).from, isNull);
  });
  testWidgets('invalid date range does not send a dashboard request', (
    tester,
  ) async {
    final repository = FakeDashboardRepository();
    await pumpAdmin(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-03-07')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-03-01')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    await tester.pumpAndSettle();
    expect(repository.requests.length, 1);
    expect(find.text('From must be on or before To.'), findsOneWidget);
  });
  testWidgets(
    'pull refresh reloads the selected period without changing filters',
    (tester) async {
      final repository = FakeDashboardRepository();
      final scope = await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      scope
          .read(dashboardQueryProvider.notifier)
          .selectRange(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 7));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('dashboard-period')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(repository.requests.length, 3);
      expect(repository.requests.last.query.toParameters(), {
        'from': '2026-03-01',
        'to': '2026-03-07',
      });
    },
  );
  for (final action in {
    'Add member': ('${AppRoutes.members}/new', null),
    'Collect dues': (AppRoutes.members, MemberOverviewFilter.dues),
    'Renewals': (AppRoutes.members, MemberOverviewFilter.expired),
    'Plans': (AppRoutes.plans, null),
  }.entries) {
    testWidgets('quick action ${action.key} opens the existing route', (
      tester,
    ) async {
      final scope = await pumpAdmin(
        tester,
        FakeDashboardRepository(),
        onboarding: action.key == 'Add member',
      );
      await tester.pumpAndSettle();
      final button = find.descendant(
        of: find.byType(DashboardQuickActions),
        matching: find.text(action.key),
      );
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(scope.read(appRouterProvider).state.uri.path, action.value.$1);
      if (action.value.$2 case final filter?) {
        expect(scope.read(memberOverviewQueryProvider).filter, filter);
      }
      if (action.key == 'Add member') {
        expect(
          scope.read(appRouterProvider).state.uri.queryParameters['gymId'],
          gymA,
        );
        expect(
          find.byKey(const ValueKey('onboarding-step-title')),
          findsOneWidget,
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scope.read(appRouterProvider).state.uri.path, AppRoutes.dashboard);
    });
  }
  testWidgets('unknown errors display only the safe dashboard fallback', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      FakeDashboardRepository()..failure = Exception('internal-server-detail'),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Retry dashboard'));
    expect(
      find.text('Dashboard could not be loaded. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal-server-detail'), findsNothing);
  });
  testWidgets(
    'dark dashboard fits 320px with double text scaling and exact money',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final repository = FakeDashboardRepository()
        ..result = GymDashboard.fromJson(
          dashboardJson(revenue: 9007199254740991),
        );
      await pumpAdmin(tester, repository);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Money collected'));
      expect(find.text('₹9,00,71,99,25,47,409.91'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CircularMetricCard),
          matching: find.byType(BackdropFilter),
        ),
        // Revenue, dues, profit, active members, check-ins and new members.
        findsNWidgets(6),
      );
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹500.00'), findsOneWidget);
      await reveal(tester, find.text('New members'));
      await reveal(tester, find.text('Add member'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dashboard works at 320px width and larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpAdmin(tester, FakeDashboardRepository());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Money collected'), 250);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Iron Signal revenue, paired metrics and dues show exact values',
    (tester) async {
      final plans = FakeMembershipRepository()..total = 37;
      await pumpAdmin(tester, FakeDashboardRepository(), plans: plans);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Active Plans'));
      final expected = {
        'Money collected': '₹12,34,567.89',
        'Pending dues': '₹500.00',
        'Total Members': '12',
        'Active Plans': '37',
      };
      for (final entry in expected.entries) {
        final card = find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(CircularMetricCard),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text(entry.value)),
          findsOneWidget,
        );
      }
      final rings = tester
          .widgetList<MetricRing>(find.byType(MetricRing))
          .toList();
      expect(rings.map((ring) => ring.color), [
        AppPalette.ember,
        DashboardAccents.pending,
        DashboardAccents.members,
        DashboardAccents.plans,
      ]);
      final revenue = find.ancestor(
        of: find.text('Money collected'),
        matching: find.byType(CircularMetricCard),
      );
      final pending = find.ancestor(
        of: find.text('Pending dues'),
        matching: find.byType(CircularMetricCard),
      );
      expect(
        tester.getTopLeft(revenue).dy,
        lessThan(tester.getTopLeft(pending).dy),
      );
      expect(
        tester.getSize(revenue).width,
        equals(tester.getSize(pending).width),
      );
      expect(plans.operations, ['plans:$gymA:1']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plan failure keeps financial metrics and hides a half-known checklist',
    (tester) async {
      final plans = FakeMembershipRepository()
        ..failure = const BillingFailure('Plans unavailable.');
      final repository = FakeDashboardRepository();
      await pumpAdmin(tester, repository, plans: plans);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹500.00'), findsOneWidget);
      expect(find.text('Finish setting up'), findsNothing);
      expect(repository.requests, hasLength(1));
    },
  );

  testWidgets(
    'setup checklist waits for the plan count, then lists missing steps',
    (tester) async {
      final plans = FakeMembershipRepository()
        ..planGate = Completer<BillingPage<MembershipPlan>>();
      await pumpAdmin(tester, FakeDashboardRepository(), plans: plans);
      await tester.pumpAndSettle();
      expect(find.text('Finish setting up'), findsNothing);
      await reveal(tester, find.text('Pending dues'));
      expect(find.text('₹500.00'), findsOneWidget);
      plans.planGate!.complete(BillingPage([], pagination(1, 0)));
      await tester.pumpAndSettle();
      await scrollToTop(tester);
      expect(find.text('Finish setting up'), findsOneWidget);
      expect(find.text('Create a membership plan'), findsOneWidget);
      expect(plans.operations, ['plans:$gymA:1']);
    },
  );
  testWidgets(
    'narrow enlarged-text shell keeps all destinations accessible without broken labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAdmin(tester, FakeDashboardRepository());
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Dashboard', 'Members', 'Trainers', 'Plans'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    for (final size in [const Size(360, 740), const Size(393, 820)]) {
      testWidgets(
        'Iron Signal summary hierarchy and scroll clearance at $size in $brightness',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await pumpAdmin(tester, FakeDashboardRepository());
          await tester.pumpAndSettle();
          final bar = tester.getRect(find.byType(NavigationBar));
          final cards = find.byType(CircularMetricCard);
          expect(cards, findsNWidgets(4));
          final revenue = tester.getRect(cards.first);
          final pending = tester.getRect(cards.at(1));
          final members = tester.getRect(cards.at(2));
          final plans = tester.getRect(cards.at(3));
          expect(revenue.bottom, lessThan(pending.top));
          expect(pending.bottom, lessThan(members.top));
          expect(members.top, plans.top);
          expect(members.height, plans.height);
          expect(members.bottom, greaterThan(pending.bottom));
          expect(pending.width, revenue.width);
          expect(revenue.bottom, lessThan(bar.top));
          for (final rect in [revenue, members, plans, pending]) {
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          expect(find.byType(MetricRing), findsNWidgets(4));
          expect(
            find.widgetWithText(ChoiceChip, 'Today').hitTestable(),
            findsOneWidget,
          );
          expect(
            find.text('Gym timezone: Asia/Kolkata').hitTestable(),
            findsNothing,
          );
          // The approved plate header makes this a scrollable overview. All dues
          // content and its action must be reachable above the fixed native tabs.
          await Scrollable.ensureVisible(
            tester.element(cards.at(1)),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(cards.at(1)).bottom, lessThan(bar.top));
          expect(find.text('View dues').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
      'four evenly spaced single-line tabs at 320dp and $scale text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpAdmin(tester, FakeDashboardRepository());
        await tester.pumpAndSettle();
        final bar = find.byType(NavigationBar);
        final destinations = find.byType(NavigationDestination);
        for (var i = 0; i < 4; i++) {
          final destination = destinations.at(i);
          final rect = tester.getRect(destination);
          expect(rect.width, closeTo(tester.getSize(bar).width / 4, .1));
          expect(rect.height, greaterThanOrEqualTo(48));
          final text = find.descendant(
            of: destination,
            matching: find.byType(Text),
          );
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: paragraph.text.toPlainText().length,
            ),
          );
          expect(boxes.map((b) => b.top).toSet(), hasLength(1));
          expect(tester.getRect(text).left, greaterThanOrEqualTo(rect.left));
          expect(tester.getRect(text).right, lessThanOrEqualTo(rect.right));
          expect(text.hitTestable(), findsOneWidget);
          expect(rect.bottom, lessThanOrEqualTo(740 - 24));
        }
        expect(
          tester.widget<NavigationBar>(bar).labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'drawer-only More returns to its previous tab with Android Back',
    (tester) async {
      final scope = await pumpAdmin(tester, FakeDashboardRepository());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Admin navigation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'More'));
      await tester.pumpAndSettle();
      expect(scope.read(appRouterProvider).state.uri.path, AppRoutes.more);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).routeInformationProvider.value.uri.path,
        AppRoutes.plans,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('to-do lists show members to act on, each with a next step', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      overviewRows: [
        FakeMemberOverviewRepository.row(
          gymId: gymA,
          daysLeft: 3,
          expiringSoon: true,
        ),
      ],
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Today’s to-do'));
    // The fake returns the same row for every list; each section renders it.
    await reveal(tester, find.textContaining('Expiring in 7 days'));
    expect(find.text('Monthly · 3 days left'), findsWidgets);
    expect(find.text('See all'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Renew'), findsWidgets);
    expect(find.byTooltip('WhatsApp Alex'), findsWidgets);
  });

  testWidgets('empty to-do lists say there is nothing to chase', (
    tester,
  ) async {
    await pumpAdmin(tester, FakeDashboardRepository());
    await tester.pumpAndSettle();
    await reveal(tester, find.text('No memberships end this week.'));
    expect(find.text('Nobody owes money right now.'), findsOneWidget);
    expect(find.text('Every expired member has renewed.'), findsOneWidget);
  });

  testWidgets('gym settings validate GSTIN and save only changed values', (
    tester,
  ) async {
    final settings = FakeGymSettingsRepository(
      settings: const GymSettings(timezone: null, timezoneConfigured: false),
    );
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      settings: settings,
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push(AppRoutes.gymSettings);
    await tester.pumpAndSettle();
    expect(find.textContaining('Not set yet'), findsOneWidget);
    // The page's vertical scroller (text fields have horizontal ones).
    final list = find
        .descendant(
          of: find.byType(GymSettingsPage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    Future<void> bottom() async {
      // A focused field keeps itself on screen; release it first.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.byKey(const ValueKey('gstin')), '1234');
    await bottom();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(settings.updates, isEmpty);
    // Jump to the top, where the timezone error is, then scroll to the GST one.
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Choose your gym’s timezone'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enter a 15-character GST number'),
      200,
      scrollable: list,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('India (IST) · Asia/Kolkata').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('gstin')),
      '27aapfu0939f1zv',
    );
    await bottom();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(settings.updates.single, {
      'timezone': 'Asia/Kolkata',
      'gstin': '27AAPFU0939F1ZV',
      'upiId': null,
      'upiPayeeName': null,
      'address': null,
    });
    expect(find.text('Gym settings saved'), findsOneWidget);
  });
  testWidgets(
    'check-in: search, refused expired member, override, today count',
    (tester) async {
      final visits = FakeVisitRepository()..expired.add(memberId);
      final scope = await pumpAdmin(
        tester,
        FakeDashboardRepository(),
        visits: visits,
        overviewRows: [
          FakeMemberOverviewRepository.row(gymId: gymA, state: 'expired'),
        ],
      );
      await tester.pumpAndSettle();
      final quick = find.descendant(
        of: find.byType(DashboardQuickActions),
        matching: find.text('Check in'),
      );
      await reveal(tester, quick);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(scope.read(appRouterProvider).state.uri.path, AppRoutes.checkIn);
      expect(find.text('Scan member QR'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Check in Alex River'));
      await tester.pumpAndSettle();
      expect(find.text('Membership not active'), findsOneWidget);
      expect(
        find.text(
          'The Monthly membership has expired. Renew it, or check in anyway.',
        ),
        findsOneWidget,
      );
      expect(visits.calls.single.override, isFalse);
      await tester.tap(find.text('Check in anyway'));
      await tester.pumpAndSettle();
      expect(visits.calls.last.override, isTrue);
      expect(find.textContaining('Checked in with override'), findsOneWidget);
      expect(find.text('Today · 1'), findsOneWidget);
    },
  );

  testWidgets('cancelling the override prompt records nothing', (tester) async {
    final visits = FakeVisitRepository()..expired.add(memberId);
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      visits: visits,
      overviewRows: [
        FakeMemberOverviewRepository.row(gymId: gymA, state: 'expired'),
      ],
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push(AppRoutes.checkIn);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Check in Alex River'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't check in"));
    await tester.pumpAndSettle();
    expect(visits.calls, hasLength(1));
    expect(visits.calls.single.override, isFalse);
    expect(find.textContaining('Checked in'), findsNothing);
  });
  testWidgets('expenses: add rent, see the month total, remove it', (
    tester,
  ) async {
    final expenses = FakeExpenseRepository();
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      expenses: expenses,
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push(AppRoutes.expenses);
    await tester.pumpAndSettle();
    expect(find.textContaining('No expenses recorded'), findsOneWidget);
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount like 2500 or 2500.50'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('expense-amount')),
      '25000',
    );
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(expenses.items.single['category'], 'rent');
    expect(expenses.items.single['amountPaise'], 2500000);
    expect(find.text('₹25,000'), findsWidgets);
    await tester.tap(find.byTooltip('Remove expense'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rent expense?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove expense'));
    await tester.pumpAndSettle();
    expect(expenses.removed, ['e1']);
    expect(find.textContaining('No expenses recorded'), findsOneWidget);
  });

  testWidgets('a negative profit is shown as a loss, never a crash', (
    tester,
  ) async {
    final repository = FakeDashboardRepository()
      ..result = GymDashboard.fromJson({
        ...dashboardJson(revenue: 100000),
        'expenses': {'periodAmountPaise': 300000, 'profitPaise': -200000},
      });
    await pumpAdmin(tester, repository);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Loss'));
    expect(find.text('₹2,000.00'), findsOneWidget);
    // Compact cards carry the caption in their accessible label.
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(r'^Loss: ₹2,000\.00\..*Spent ₹3,000')),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
  Future<void> openAdjustments(
    WidgetTester tester,
    ProviderContainer scope,
  ) async {
    final gym = scope.read(adminGymProvider)!;
    Navigator.of(
      tester.element(find.byType(Scaffold).first),
      rootNavigator: true,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: SingleChildScrollView(
            child: MembershipAdjustmentsCard(
              scope: (userId: gym.userId, gymId: gym.gymId, memberId: memberId),
              subscriptionId: 'subscription-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('freeze: preview shows the return day and new end, then saves', (
    tester,
  ) async {
    final adjustments = FakeAdjustmentRepository();
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      adjustments: adjustments,
    );
    await tester.pumpAndSettle();
    await openAdjustments(tester, scope);
    expect(find.text('Frozen 0 of 30 days · Ends 29 Jan 2027'), findsOneWidget);
    await tester.tap(find.text('Freeze membership'));
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsOneWidget);
    expect(
      find.text('Back on 21 Nov 2026. Membership now ends 5 Feb 2027.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Freeze for 7 days'));
    await tester.tap(find.text('Freeze for 7 days'));
    await tester.pumpAndSettle();
    expect(adjustments.calls, ['freeze:2026-11-14:7']);
    expect(find.text('End early'), findsOneWidget);
  });

  testWidgets('freeze is explained, not offered, when the plan is too short', (
    tester,
  ) async {
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      adjustments: FakeAdjustmentRepository(
        json: adjustmentsJson(durationDays: 30, blocker: 'plan_too_short'),
      ),
    );
    await tester.pumpAndSettle();
    await openAdjustments(tester, scope);
    expect(find.text('Freeze membership'), findsNothing);
    expect(
      find.text('Only plans of 90 days or more can be frozen.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'discount: percent previews rupees; more than unpaid is refused',
    (tester) async {
      final adjustments = FakeAdjustmentRepository(
        json: adjustmentsJson(paidPaise: 300000),
      );
      final scope = await pumpAdmin(
        tester,
        FakeDashboardRepository(),
        adjustments: adjustments,
      );
      await tester.pumpAndSettle();
      await openAdjustments(tester, scope);
      await tester.tap(find.text('Give discount'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('discount-value')),
        '1500',
      );
      await tester.pumpAndSettle();
      expect(find.text('That is more than the unpaid ₹1,000.'), findsOneWidget);
      await tester.tap(find.text('Percent %'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('discount-value')),
        '10',
      );
      await tester.pumpAndSettle();
      expect(find.text('₹400 off · Still due ₹600'), findsOneWidget);
      await tester.ensureVisible(find.text('Give ₹400 discount'));
      await tester.tap(find.text('Give ₹400 discount'));
      await tester.pumpAndSettle();
      expect(adjustments.calls, ['discount:10.0%']);
    },
  );
  testWidgets('dashboard lists enquiry follow-ups and birthdays this week', (
    tester,
  ) async {
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      leads: FakeLeadRepository(),
      birthdays: [
        UpcomingBirthday.fromJson({
          'member': {
            'id': memberId,
            'memberCode': 'ME01',
            'firstName': 'Priya',
            'lastName': 'Verma',
            'phone': '9876543202',
            'status': 'active',
          },
          'daysUntil': 2,
          'turning': 28,
        }),
      ],
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Enquiry follow-ups · 1'));
    expect(find.text('Kabir Malhotra'), findsOneWidget);
    await reveal(tester, find.text('Birthdays this week'));
    expect(find.text('In 2 days · turns 28'), findsOneWidget);
    expect(find.byTooltip('Wish Priya on WhatsApp'), findsOneWidget);
    await reveal(tester, find.text('Enquiry follow-ups · 1'));
    await tester.tap(find.text('Enquiry follow-ups · 1'));
    await tester.pumpAndSettle();
    expect(scope.read(appRouterProvider).state.uri.path, AppRoutes.leads);
  });

  testWidgets('add enquiry validates, saves and opens it', (tester) async {
    final leads = FakeLeadRepository(leads: []);
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      leads: leads,
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push(AppRoutes.leads);
    await tester.pumpAndSettle();
    expect(find.text('No follow-ups due. Nice work.'), findsOneWidget);
    await tester.tap(find.text('Add enquiry'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save enquiry'));
    await tester.tap(find.text('Save enquiry'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Enter a phone number'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lead-first')), 'Meera');
    await tester.enterText(
      find.byKey(const ValueKey('lead-phone')),
      '90000 10002',
    );
    await tester.ensureVisible(find.text('Save enquiry'));
    await tester.tap(find.text('Save enquiry'));
    await tester.pumpAndSettle();
    expect(leads.calls, ['create:Meera:90000 10002:walk_in']);
    expect(
      scope.read(appRouterProvider).state.uri.path,
      startsWith('${AppRoutes.leads}/'),
    );
    expect(find.text('Convert to member'), findsOneWidget);
  });

  testWidgets(
    'enquiry: start trial, lost needs a reason, convert prefills Add member',
    (tester) async {
      final leads = FakeLeadRepository();
      final scope = await pumpAdmin(
        tester,
        FakeDashboardRepository(),
        leads: leads,
        onboarding: true,
      );
      await tester.pumpAndSettle();
      scope.read(appRouterProvider).push('${AppRoutes.leads}/$leadA');
      await tester.pumpAndSettle();
      expect(find.text('Kabir Malhotra'), findsOneWidget);
      await tester.tap(find.text('Start 3-day trial'));
      await tester.pumpAndSettle();
      expect(leads.calls, ['trial']);
      expect(find.text('Start 3-day trial'), findsNothing);
      await tester.tap(find.text('Mark lost'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark lost'));
      await tester.pumpAndSettle();
      expect(leads.calls, ['trial'], reason: 'no reason, nothing saved');
      await tester.tap(find.text('Convert to member'));
      await tester.pumpAndSettle();
      expect(
        scope.read(appRouterProvider).state.uri.path,
        '${AppRoutes.members}/new',
      );
      expect(
        scope.read(appRouterProvider).state.uri.queryParameters.keys,
        ['gymId'],
        reason: 'name and phone are never put in the URL',
      );
      String field(String key) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(field('firstName'), 'Kabir');
      expect(field('lastName'), 'Malhotra');
      expect(field('phone'), '90000 10001');
    },
  );
  testWidgets('mark lost saves the reason and offers to reopen', (
    tester,
  ) async {
    final leads = FakeLeadRepository();
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      leads: leads,
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push('${AppRoutes.leads}/$leadA');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mark lost'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark lost'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lost-reason')),
      'Too far',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark lost'));
    await tester.pumpAndSettle();
    expect(leads.calls, ['update:{status: lost, lostReason: Too far}']);
    expect(find.text('Reopen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a phone that already has an open enquiry opens it', (
    tester,
  ) async {
    final leads = FakeLeadRepository()..duplicateOf = leadA;
    final scope = await pumpAdmin(
      tester,
      FakeDashboardRepository(),
      leads: leads,
    );
    await tester.pumpAndSettle();
    scope.read(appRouterProvider).push(AppRoutes.leads);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add enquiry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lead-first')), 'Kabir');
    await tester.enterText(
      find.byKey(const ValueKey('lead-phone')),
      '90000 10001',
    );
    await tester.ensureVisible(find.text('Save enquiry'));
    await tester.tap(find.text('Save enquiry'));
    await tester.pumpAndSettle();
    expect(
      scope.read(appRouterProvider).state.uri.path,
      '${AppRoutes.leads}/$leadA',
    );
    expect(
      find.text('Already an open enquiry for this number. Opening it.'),
      findsOneWidget,
    );
  });
}
