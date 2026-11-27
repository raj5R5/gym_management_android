import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import '../members/photo_fakes.dart';
import '../members/photo_test_support.dart' show PhotoRepositoryFake;
import 'package:gym_management_app/features/members/photos/member_photo_widgets.dart';
import 'package:gym_management_app/shared/widgets/membership_date_range.dart';
import 'package:gym_management_app/features/members/presentation/member_details_page.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../members/onboarding_fakes.dart' show TestOnboardingStorage;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/shared/widgets/soft_panel.dart';
import 'package:gym_management_app/features/members/presentation/member_list_widgets.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/presentation/circular_metric_card.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/memberships/providers/plan_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'billing_fakes.dart';
import 'payment_fakes.dart';
import 'package:gym_management_app/features/memberships/presentation/billing_components.dart';
import 'package:gym_management_app/features/memberships/presentation/record_payment_sheet.dart';
import 'package:gym_management_app/features/memberships/data/payment_repository.dart';

void main() {
  setUpAll(() async {
    for (final family in ['Inter', 'SpaceGrotesk']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });

  late FakePaymentRepository payments;
  late DueMembersFake members;
  late FakeMembershipRepository plans;
  late ProviderContainer container;
  Future<void> mount(
    WidgetTester tester, {
    TestOnboardingStorage? recoveryStorage,
    PhotoRepositoryFake? photoRepository,
  }) async {
    payments = FakePaymentRepository();
    members = DueMembersFake();
    plans = FakeMembershipRepository();
    payments.onCollection = members.collect;
    payments.memberLookup = () => members.profiles.first;
    container = ProviderContainer(
      overrides: [
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: recoveryStorage ?? TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
        if (photoRepository != null)
          memberPhotoRepositoryProvider.overrideWithValue(photoRepository),
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(
            apiBaseUrl: 'https://api.example.invalid/api/v1/',
          ),
        ),
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()..value = syntheticCredential(),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(members),
        membershipRepositoryProvider.overrideWithValue(plans),
        paymentRepositoryProvider.overrideWithValue(payments),
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
  }

  Future<void> tapCard(WidgetTester tester, String title) async {
    final card = find.byWidgetPredicate(
      (widget) => widget is CircularMetricCard && widget.title == title,
    );
    if (card.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await mount(tester);
    container
        .read(appRouterProvider)
        .go(
          '${AppRoutes.members}/$memberId/membership/$subscriptionId?gymId=$gymA',
        );
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Record Payment'));
    await tester.tap(find.text('Record Payment'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm payment'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'retry progress does not present a previous refresh error as the latest outcome',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinancialRefreshStatus(
              loading: true,
              error: const BillingFailure('Previous attempt failed.'),
              retry: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Updating…'), findsOneWidget);
      expect(find.textContaining('Refresh failed.'), findsNothing);
      expect(find.text('Previous attempt failed.'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinancialRefreshStatus(
              loading: false,
              error: const BillingFailure('Previous attempt failed.'),
              retry: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Refresh failed.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'initial dues failure shows no misleading zero or partial total',
    (tester) async {
      await mount(tester);
      members.failure = const BillingFailure('Balances could not be loaded.');
      await tapCard(tester, 'Pending Amount');
      expect(find.text('Balances could not be loaded.'), findsOneWidget);
      expect(find.text('₹0.00'), findsNothing);
      expect(find.text('Total current dues'), findsNothing);
      expect(find.text('Record Payment'), findsNothing);
      members.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('₹500.00'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'financial transactions wrap on a narrow screen in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await mount(tester);
        payments.transactionReference = 'UPI-${List.filled(80, 'x').join()}';
        container
            .read(appRouterProvider)
            .go(
              '${AppRoutes.revenue}?gymId=$gymA&from=2026-03-01&to=2026-03-02',
            );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Transaction reference'),
          180,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Transaction reference'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<void> showRevenue(WidgetTester tester) async {
    container
        .read(appRouterProvider)
        .go('${AppRoutes.revenue}?gymId=$gymA&from=2026-03-01&to=2026-03-02');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Membership Details passes the saved member name and code to collection',
    (tester) async {
      await mount(tester);
      members.profiles = [
        MemberProfile.fromJson(profileJson(firstName: 'Taylor')),
      ];
      container
          .read(appRouterProvider)
          .go(
            '${AppRoutes.members}/$memberId/membership/$subscriptionId?gymId=$gymA',
          );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Record Payment'));
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<RecordPaymentSheet>(
        find.byType(RecordPaymentSheet),
      );
      expect(sheet.memberName, 'Taylor River');
      expect(sheet.memberCode, 'ME01');
      expect(find.text('Taylor River'), findsOneWidget);
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(find.text('Monthly'), findsWidgets);
      expect(find.text('Remaining balance: ₹500.00'), findsOneWidget);
      expect(find.text('Membership payment'), findsNothing);
    },
  );

  testWidgets(
    'revenue shows genuine reference, successful status and gym-local payment time',
    (tester) async {
      await mount(tester);
      payments.transactionReference = 'UPI-PILOT-123';
      await showRevenue(tester);
      expect(
        find.text('Paid: Mar 1, 2026 · 5:30 PM · Asia/Kolkata'),
        findsOneWidget,
      );
      expect(find.text('Successful payment'), findsOneWidget);
      expect(find.text('Payment method: Cash'), findsOneWidget);
      expect(find.text('Transaction reference'), findsOneWidget);
      expect(find.text('UPI-PILOT-123'), findsOneWidget);
      expect(find.textContaining('Receipt:'), findsNothing);
      expect(find.text('000000000000000000000066'), findsNothing);
      expect(find.textContaining('T12:00:00'), findsNothing);
    },
  );

  testWidgets(
    'revenue keeps complete same-range content while refreshing and after failure',
    (tester) async {
      await mount(tester);
      await showRevenue(tester);
      payments.revenueGate = Completer<RevenuePage>();
      await tester.tap(find.byTooltip('Refresh revenue'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('revenueTotal'))).data,
        '₹1,000.00',
      );
      expect(find.text('Last verified revenue'), findsOneWidget);
      expect(find.textContaining('Updating…'), findsOneWidget);
      expect(payments.ranges, hasLength(2));
      expect(payments.ranges.last.range.toParameters(), {
        'from': '2026-03-01',
        'to': '2026-03-02',
      });
      payments.revenueGate!.completeError(
        const BillingFailure('Could not refresh payments.'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Refresh failed.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('revenueTotal'))).data,
        '₹1,000.00',
      );
      await reveal(tester, find.text('Alex River'));
      expect(find.text('Alex River'), findsOneWidget);
      payments.revenueGate = null;
      payments.revenuePaise = 120000;
      await reveal(tester, find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('revenueTotal'))).data,
        '₹1,200.00',
      );
      expect(find.textContaining('Refresh failed.'), findsNothing);
      expect(payments.ranges, hasLength(3));
    },
  );

  testWidgets(
    'dues retains search, sort and complete totals on failed refresh; payment is gated',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Pending Amount');
      await tester.enterText(find.byType(TextField), 'ME01');
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name A–Z').last);
      await tester.pumpAndSettle();
      members.listGate = Completer<MembersPage>();
      await tester.tap(find.byTooltip('Refresh dues'));
      await tester.pump();
      expect(find.text('Last verified dues'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ME01',
      );
      members.listGate!.completeError(
        const BillingFailure('Balances unavailable.'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Refresh failed.'), findsOneWidget);
      expect(find.text('Record Payment'), findsNothing);
      expect(payments.collections, isEmpty);
      await reveal(tester, find.text('Alex River'));
      expect(find.text('₹500 due'), findsOneWidget);
      await reveal(tester, find.byType(DropdownButtonFormField<bool>));
      expect(
        tester
            .widget<DropdownButtonFormField<bool>>(
              find.byType(DropdownButtonFormField<bool>),
            )
            .initialValue,
        false,
      );
      members.listGate = null;
      await reveal(tester, find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Total current dues'));
      expect(find.text('Total current dues'), findsOneWidget);
      expect(find.textContaining('Refresh failed.'), findsNothing);
      await reveal(tester, find.byType(TextField));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ME01',
      );
    },
  );

  testWidgets(
    'a failed partial dues read never replaces the last complete total',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Pending Amount');
      members.debts[memberId]!.first.remove('paymentSummary');
      await tester.tap(find.byTooltip('Refresh dues'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refresh failed.'), findsOneWidget);
      await reveal(tester, find.text('Last verified dues'));
      expect(find.text('Last verified dues'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      expect(find.text('₹0.00'), findsNothing);
    },
  );

  for (final financialPage in ['revenue', 'dues']) {
    testWidgets(
      '$financialPage identity refreshes after a real edit-provider save',
      (tester) async {
        await mount(tester);
        if (financialPage == 'revenue') {
          await showRevenue(tester);
        } else {
          await tapCard(tester, 'Pending Amount');
          await tester.enterText(find.byType(TextField), 'ME01');
        }
        await reveal(tester, find.text('Alex River'));
        await tester.tap(find.text('Alex River'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Edit member'));
        await tester.tap(find.text('Edit member'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('firstName')),
          'Taylor',
        );
        await reveal(tester, find.byKey(const ValueKey('phone')));
        await tester.enterText(
          find.byKey(const ValueKey('phone')),
          '9876543299',
        );
        await reveal(
          tester,
          find.byType(DropdownButtonFormField<MemberStatus>),
        );
        await tester.tap(find.byType(DropdownButtonFormField<MemberStatus>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('inactive').last);
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(members.writes, hasLength(1));
        // Return to the financial page retained beneath member details.
        container.read(appRouterProvider).pop();
        await tester.pumpAndSettle();
        expect(find.text('Taylor River'), findsOneWidget);
        expect(find.text('Alex River'), findsNothing);
        if (financialPage == 'revenue') {
          expect(payments.ranges.last.range.toParameters(), {
            'from': '2026-03-01',
            'to': '2026-03-02',
          });
          expect(payments.ranges, hasLength(2));
        } else {
          await reveal(tester, find.byType(TextField));
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'ME01',
          );
          expect(find.text('₹500.00'), findsOneWidget);
          await reveal(tester, find.text('₹500 due'));
          expect(find.text('₹500 due'), findsOneWidget);
          expect(find.textContaining('9876543299'), findsNothing);
          expect(find.text('Member code: ME01'), findsOneWidget);
          expect(members.profiles.single.status, MemberStatus.inactive);
        }
      },
    );
  }

  testWidgets(
    'revenue card opens exact selected range and successful payment details',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Total Revenue');
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppRoutes.revenue,
      );
      expect(payments.ranges.single.range.toParameters(), {
        'from': '2026-03-01',
        'to': '2026-03-01',
      });
      expect(find.text('Revenue Details'), findsOneWidget);
      expect(find.text('1 successful payment'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('revenueTotal'))).data,
        '₹1,000.00',
      );
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppRoutes.dashboard,
      );
    },
  );
  testWidgets('member card preserves current member search/status', (
    tester,
  ) async {
    await mount(tester);
    container
        .read(memberQueryProvider.notifier)
        .apply(search: 'Alex', status: MemberStatus.inactive);
    await tapCard(tester, 'Total Members');
    expect(container.read(appRouterProvider).state.uri.path, AppRoutes.members);
    expect(members.listCalls.last.query.search, 'Alex');
    expect(members.listCalls.last.query.status, MemberStatus.inactive);
  });
  testWidgets(
    'active-plan card uses existing plans screen with server active filter',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Active Plans');
      expect(container.read(appRouterProvider).state.uri.path, AppRoutes.plans);
      expect(
        container.read(appRouterProvider).state.uri.queryParameters['status'],
        'active',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Active only'))
            .selected,
        isTrue,
      );
      expect(
        plans.operations.where((value) => value.startsWith('managePlans:')),
        isEmpty,
      );
      expect(
        plans.operations.where((value) => value.startsWith('plans:')),
        hasLength(2),
      );
    },
  );
  testWidgets(
    'dues card shows positive balance, search and member-details navigation',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Pending Amount');
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppRoutes.outstandingDues,
      );
      expect(find.text('₹500.00'), findsOneWidget);
      expect(find.text('Alex River'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'absent');
      await tester.pumpAndSettle();
      expect(find.text('No members match your search.'), findsOneWidget);
      expect(find.text('Alex River'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Alex');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Alex River'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        '${AppRoutes.members}/$memberId',
      );
    },
  );
  testWidgets(
    'Members and dues share photo sizes with naturally sized identity and dues footers',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      members.populated = true;
      await tapCard(tester, 'Pending Amount');
      await reveal(tester, find.text('Alex River'));
      final duesCard = find.ancestor(
        of: find.text('Alex River'),
        matching: find.byType(Card),
      );
      final duesSize = tester.getSize(duesCard);

      final duesPhoto = tester.getSize(
        find.descendant(of: duesCard, matching: find.byType(MemberPhotoAvatar)),
      );
      expect(duesPhoto.height, 168);
      expect(find.text('Total across 1 unpaid membership'), findsOneWidget);
      expect(find.text('Current membership dates'), findsOneWidget);
      container.read(appRouterProvider).go(AppRoutes.members);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Alex River'));
      final memberCard = find.ancestor(
        of: find.text('Alex River'),
        matching: find.byType(Card),
      );

      expect(tester.getSize(memberCard).width, duesSize.width);
      expect(tester.getSize(memberCard).height, greaterThan(duesPhoto.height));
      expect(duesSize.height, greaterThan(duesPhoto.height));
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(
        tester.getSize(
          find.descendant(
            of: memberCard,
            matching: find.byType(MemberPhotoAvatar),
          ),
        ),
        duesPhoto,
      );
      expect(find.text('Active'), findsNothing);
      expect(find.byTooltip('Active membership'), findsOneWidget);
      expect(find.text('Payment due'), findsNothing);
      expect(find.text('₹500.00 due'), findsOneWidget);
      expect(find.text('1 Mar 2026 –'), findsOneWidget);
      expect(find.text('31 Mar 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'polished dues summary and member identity reuse pending warning colors',
    (tester) async {
      await mount(tester);
      await tapCard(tester, 'Pending Amount');
      final summary = tester.widget<SoftPanel>(
        find.byKey(const ValueKey('dues-summary')),
      );
      expect(summary.backgroundColor, PendingColors.surface);
      expect(
        find.textContaining('Independent of the selected revenue period'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Alex River'));
      expect(find.text('AR'), findsOneWidget);
      expect(find.text('₹500 due'), findsOneWidget);
      expect(find.byType(MemberStatusBadge), findsNothing);
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(find.textContaining('9876543210'), findsNothing);
      expect(find.textContaining('Amount paid:'), findsNothing);
      expect(find.text('Record Payment'), findsNothing);
      expect(find.text('Monthly'), findsNothing);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '1 Mar 2026 – 31 Mar 2026',
      );
      final card = tester.widget<Card>(
        find.ancestor(of: find.text('₹500 due'), matching: find.byType(Card)),
      );
      expect(card.color, PendingColors.surface);
      expect(find.textContaining(subscriptionId), findsNothing);
    },
  );

  testWidgets(
    'multiple unpaid memberships deduplicate totals and target the correct payment',
    (tester) async {
      const previousId = '000000000000000000000023';
      await mount(tester);
      members.debts[memberId] = [
        debtJson()..['planNameSnapshot'] = 'Current monthly',
        debtJson(id: previousId, balance: 70000, status: 'expired')
          ..['planNameSnapshot'] = 'Previous monthly',
        debtJson(id: gymA, balance: 90000, status: 'cancelled')
          ..['planNameSnapshot'] = 'Cancelled monthly',
      ];
      await tapCard(tester, 'Pending Amount');
      expect(find.text('₹1,200.00'), findsOneWidget);
      final data = container.read(outstandingDuesProvider).asData!.value!;
      expect(data.totalPaise, 120000);
      expect(data.members.single.memberships, hasLength(2));
      await reveal(tester, find.text('₹1,200 due'));
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '1 Mar 2026 – 31 Mar 2026',
      );
      expect(find.text('Record Payment'), findsNothing);
      expect(find.text('Previous monthly'), findsNothing);
      expect(find.text('Cancelled monthly'), findsNothing);
      final dashboard =
          container.read(dashboardRepositoryProvider)
              as FakeDashboardRepository;
      final reads = dashboard.requests.length;
      payments.onCollection = (collection) {
        members.collect(collection);
        dashboard.result = GymDashboard.fromJson(
          dashboardJson(outstanding: 110000),
        );
      };
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MemberDetailsPage>(find.byType(MemberDetailsPage))
            .memberId,
        memberId,
      );
      await reveal(tester, find.text('Membership & payments'));
      await tester.tap(find.text('Membership & payments'));
      await tester.pumpAndSettle();
      final previous = find.widgetWithText(ListTile, 'Previous monthly');
      await reveal(tester, previous);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Record Payment'));
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<RecordPaymentSheet>(
        find.byType(RecordPaymentSheet),
      );
      expect(sheet.scope.subscriptionId, previousId);
      expect(sheet.scope.member.memberId, memberId);
      expect(sheet.scope.member.gymId, gymA);
      expect(sheet.memberName, 'Alex River');
      expect(sheet.memberCode, 'ME01');
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await confirm(tester);
      expect(payments.collections, hasLength(1));
      expect(payments.collections.single.subscriptionId, previousId);
      expect(payments.collections.single.body['amountPaise'], 10000);
      expect(find.text('Payment recorded'), findsOneWidget);
      expect(
        members
            .debts[memberId]!
            .first['paymentSummary']['remainingBalancePaise'],
        50000,
      );
      expect(
        members.debts[memberId]![1]['paymentSummary']['remainingBalancePaise'],
        60000,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      container
          .read(appRouterProvider)
          .go('${AppRoutes.outstandingDues}?gymId=$gymA');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Total current dues'));
      expect(find.text('₹1,100.00'), findsOneWidget);
      expect(
        container.read(outstandingDuesProvider).asData!.value!.totalPaise,
        110000,
      );
      expect(dashboard.requests.length, greaterThan(reads));
      expect(
        container
            .read(dashboardProvider)
            .asData!
            .value!
            .payments
            .outstandingAmountPaise,
        110000,
      );
    },
  );

  testWidgets(
    'missing saved balance blocks the initial dues list instead of showing zero',
    (tester) async {
      await mount(tester);
      members.debts[memberId]!.first.remove('paymentSummary');
      await tapCard(tester, 'Pending Amount');
      expect(
        find.textContaining('Membership balances could not be verified'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dues-summary')), findsNothing);
      expect(find.text('₹0.00'), findsNothing);
      expect(find.text('Record Payment'), findsNothing);
    },
  );

  testWidgets('search and name sorting preserve the whole-gym dues summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    members.profiles.add(
      MemberProfile.fromJson(profileJson(firstName: 'Zed')..['id'] = gymB),
    );
    members.debts[gymB] = [
      debtJson(id: '000000000000000000000024', balance: 70000),
    ];
    await tapCard(tester, 'Pending Amount');
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(gymB))).dy,
      tester.getTopLeft(find.byKey(const ValueKey(memberId))).dy,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(gymB))).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey(memberId))).dx),
    );
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A–Z').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(memberId))).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey(gymB))).dx),
    );
    await tester.enterText(find.byType(TextField), 'Zed');
    await tester.pumpAndSettle();
    expect(find.text('Zed River'), findsOneWidget);
    expect(find.text('Alex River'), findsNothing);
    expect(find.text('₹1,200.00'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'dues uses full-width cover photos and an initials fallback in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final photos = PhotoRepositoryFake();
        await mount(tester, photoRepository: photos);
        members.profiles = [
          MemberProfile.fromJson({
            ...profileJson(),
            'photoUrl': 'gyms/$gymA/members/$memberId/photo?v=1',
            'photoRevision': 1,
          }),
          MemberProfile.fromJson({
            ...profileJson(),
            'id': gymB,
            'firstName': 'Zed',
          }),
        ];
        members.debts[gymB] = [debtJson(balance: 70000, status: 'expired')];
        await tapCard(tester, 'Pending Amount');
        await reveal(tester, find.text('Alex River'));
        final photo = find.byWidgetPredicate(
          (widget) =>
              widget is MemberPhotoAvatar && widget.member.id == memberId,
        );
        final card = find.byKey(const ValueKey(memberId));
        final photoBounds = tester.getRect(photo);
        final cardBounds = tester.getRect(card);
        expect(photoBounds.width, cardBounds.width);
        expect(photoBounds.height, 168);
        expect(
          tester
              .widget<Image>(
                find.descendant(of: photo, matching: find.byType(Image)),
              )
              .fit,
          BoxFit.cover,
        );
        expect(
          find.descendant(of: photo, matching: find.byType(ClipOval)),
          findsNothing,
        );
        expect(photos.reads, 1);
        expect(find.text('ZR'), findsOneWidget);
        expect(find.text('₹1,200.00'), findsOneWidget);
        expect(find.text('₹500 due'), findsOneWidget);
        expect(find.text('₹700 due'), findsOneWidget);
        expect(find.text('Expired'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(payments.collections, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.invalidate(memberPhotoImageProvider);
        await tester.pump(const Duration(milliseconds: 1));
      },
    );

    testWidgets(
      'dues card with expired debt fits 320px and double text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await mount(tester);
        members.debts[memberId] = [debtJson(status: 'expired')];
        await tapCard(tester, 'Pending Amount');
        await reveal(tester, find.text('Expired'));
        expect(
          tester
              .widget<StatusPill>(find.widgetWithText(StatusPill, 'Expired'))
              .tone,
          AppTone.expired,
        );
        expect(find.text('₹500 due'), findsOneWidget);
        expect(find.text('Record Payment'), findsNothing);
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byKey(const ValueKey(memberId)));
        expect(card.width, lessThanOrEqualTo(320));
      },
    );
  }
  testWidgets(
    'dues labels the total across memberships separately from current saved dates',
    (tester) async {
      await mount(tester);
      members.debts[memberId] = [
        debtJson(id: gymB, balance: 70000, status: 'expired')
          ..addAll({'startDate': '2025-01-01', 'endDate': '2025-02-01'}),
        debtJson()
          ..addAll({'startDate': '2026-10-12', 'endDate': '2026-12-12'}),
      ];
      await tapCard(tester, 'Pending Amount');
      expect(find.text('₹1,200 due'), findsOneWidget);
      expect(find.text('Total across 2 unpaid memberships'), findsOneWidget);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '12 Oct 2026 – 12 Dec 2026',
      );
      expect(find.text('Current membership dates'), findsOneWidget);
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
      expect(find.text('Record Payment'), findsNothing);
    },
  );
  testWidgets(
    'latest expired dues uses saved dates and neutral background with a due amount',
    (tester) async {
      await mount(tester);
      members.debts[memberId] = [
        debtJson(status: 'expired')
          ..addAll({'startDate': '2025-01-01', 'endDate': '2025-02-01'}),
        debtJson(id: gymB, balance: 70000, status: 'expired')
          ..addAll({'startDate': '2026-09-01', 'endDate': '2026-10-01'}),
      ];
      await tapCard(tester, 'Pending Amount');
      expect(find.text('₹1,200 due'), findsOneWidget);
      expect(find.text('Total across 2 unpaid memberships'), findsOneWidget);
      expect(
        tester
            .widget<MembershipDateRange>(find.byType(MembershipDateRange))
            .label,
        '1 Sep 2026 – 1 Oct 2026',
      );
      expect(find.text('Latest expired membership dates'), findsOneWidget);
      expect(
        tester
            .widget<Card>(
              find.ancestor(
                of: find.text('₹1,200 due'),
                matching: find.byType(Card),
              ),
            )
            .color,
        AppPalette.mutedGrey,
      );
      expect(
        tester
            .widget<StatusPill>(find.widgetWithText(StatusPill, 'Expired'))
            .tone,
        AppTone.expired,
      );
    },
  );
  testWidgets(
    'dues grid is two columns on a normal phone and entire card opens correct member',
    (tester) async {
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      members.profiles.add(
        MemberProfile.fromJson(
          profileJson(firstName: 'Zed')
            ..addAll({'id': gymB, 'memberCode': 'ME02'}),
        ),
      );
      members.debts[gymB] = [
        debtJson(id: '000000000000000000000024', balance: 70001),
      ];
      await tapCard(tester, 'Pending Amount');
      final first = tester.getRect(find.byKey(const ValueKey(gymB)));
      final second = tester.getRect(find.byKey(const ValueKey(memberId)));
      expect(first.top, second.top);
      expect(second.left, greaterThan(first.right));
      expect(find.text('₹700.01 due'), findsOneWidget);
      await tester.tap(find.text('₹700.01 due'));
      await tester.pumpAndSettle();
      final detail = tester.widget<MemberDetailsPage>(
        find.byType(MemberDetailsPage),
      );
      expect(detail.memberId, gymB);
      expect(detail.gymId, gymA);
      expect(payments.collections, isEmpty);
    },
  );

  Future<void> showMemberDetails(WidgetTester tester) async {
    container
        .read(appRouterProvider)
        .go('${AppRoutes.members}/$memberId?gymId=$gymA');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Pay Now opens the only unpaid membership with real identity and prevents duplicate sheets',
    (tester) async {
      await mount(tester);
      await showMemberDetails(tester);
      await reveal(tester, find.text('Collect payment'));
      await tester.tap(find.text('Collect payment'));
      await tester.tap(find.text('Collect payment'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentSheet), findsOneWidget);
      expect(find.text('Choose membership to pay'), findsNothing);
      final form = tester.widget<RecordPaymentSheet>(
        find.byType(RecordPaymentSheet),
      );
      expect(form.scope.subscriptionId, subscriptionId);
      expect(form.memberName, 'Alex River');
      expect(form.memberCode, 'ME01');
      expect(find.textContaining('₹500.00'), findsWidgets);
      expect(payments.collections, isEmpty);
    },
  );
  testWidgets(
    'Pay Now selects only verified unpaid non-cancelled periods, including expired ones',
    (tester) async {
      await mount(tester);
      members.debts[memberId] = [
        debtJson(),
        debtJson(id: gymB, status: 'expired', balance: 70000)
          ..['planNameSnapshot'] = 'Previous monthly',
        debtJson(id: '000000000000000000000024', balance: 0)
          ..['planNameSnapshot'] = 'Fully paid plan',
        debtJson(
          id: '000000000000000000000025',
          status: 'cancelled',
          balance: 90000,
        )..['planNameSnapshot'] = 'Cancelled plan',
      ];
      await showMemberDetails(tester);
      await reveal(tester, find.text('Collect payment'));
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      expect(find.text('Choose membership to pay'), findsOneWidget);
      expect(find.byType(RecordPaymentSheet), findsNothing);
      expect(find.text('Fully paid plan'), findsNothing);
      expect(find.text('Cancelled plan'), findsNothing);
      expect(find.text('Expired · ₹700.00 remaining'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(MembershipDateRange),
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.byKey(ValueKey('pay-membership-$gymB')));
      await tester.pumpAndSettle();
      final form = tester.widget<RecordPaymentSheet>(
        find.byType(RecordPaymentSheet),
      );
      expect(form.scope.subscriptionId, gymB);
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await confirm(tester);
      expect(payments.collections.single.subscriptionId, gymB);
      expect(
        members.debts[memberId]![0]['paymentSummary']['remainingBalancePaise'],
        50000,
      );
      expect(
        members.debts[memberId]![1]['paymentSummary']['remainingBalancePaise'],
        60000,
      );
    },
  );
  Future<void> openSelector(WidgetTester tester) async {
    await mount(tester);
    members.debts[memberId]!.add(debtJson(id: gymB, status: 'expired'));
    await showMemberDetails(tester);
    await reveal(tester, find.text('Collect payment'));
    await tester.tap(find.text('Collect payment'));
    await tester.pumpAndSettle();
    expect(find.text('Choose membership to pay'), findsOneWidget);
  }

  Finder selectorContent(Finder target) =>
      find.descendant(of: find.byType(BottomSheet), matching: target);

  testWidgets('selector retains header and close while balances reload', (
    tester,
  ) async {
    await openSelector(tester);
    final scope = scopeFor(container.read(adminGymProvider)!, memberId);
    final gate = Completer<MembershipHistory>();
    members.historyGate = gate;
    container.invalidate(memberMembershipsProvider(scope));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Choose membership to pay'), findsOneWidget);
    expect(
      find.byTooltip('Close membership selection').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Checking outstanding memberships…'), findsOneWidget);
    expect(
      selectorContent(find.byType(LinearProgressIndicator)),
      findsOneWidget,
    );
    expect(selectorContent(find.byType(ListTile)), findsNothing);
    expect(find.byType(RecordPaymentSheet), findsNothing);
    expect(payments.collections, isEmpty);
    members.historyGate = null;
    gate.complete(await members.memberships(gymA, memberId, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('pay-membership-$gymB')), findsOneWidget);
    await tester.tap(find.byTooltip('Close membership selection'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  for (final invalidBalance in [false, true]) {
    testWidgets(
      'selector error retains close and retries existing balance reads, invalidBalance=$invalidBalance',
      (tester) async {
        await openSelector(tester);
        final scope = scopeFor(container.read(adminGymProvider)!, memberId);
        if (invalidBalance) {
          members.debts[memberId]!.first.remove('paymentSummary');
        } else {
          members.failure = const BillingFailure(
            'Membership lookup is temporarily unavailable.',
          );
        }
        container.invalidate(memberMembershipsProvider(scope));
        await tester.pumpAndSettle();
        expect(find.text('Choose membership to pay'), findsOneWidget);
        expect(
          find.byTooltip('Close membership selection').hitTestable(),
          findsOneWidget,
        );
        expect(selectorContent(find.byType(BillingError)), findsOneWidget);
        expect(selectorContent(find.byType(ListTile)), findsNothing);
        expect(find.byType(RecordPaymentSheet), findsNothing);
        final before = members.operations
            .where((entry) => entry.startsWith('memberships:'))
            .length;
        members.failure = null;
        members.debts[memberId]![0] = debtJson();
        final retry = selectorContent(find.text('Retry'));
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(
          members.operations
              .where((entry) => entry.startsWith('memberships:'))
              .length,
          greaterThan(before),
        );
        expect(selectorContent(find.byType(BillingError)), findsNothing);
        expect(find.byKey(ValueKey('pay-membership-$gymB')), findsOneWidget);
        expect(payments.collections, isEmpty);
      },
    );
  }

  testWidgets(
    'selector explicitly shows no outstanding memberships after balances settle',
    (tester) async {
      await openSelector(tester);
      final scope = scopeFor(container.read(adminGymProvider)!, memberId);
      members.debts[memberId] = [
        debtJson(balance: 0),
        debtJson(id: gymB, status: 'expired', balance: 0),
      ];
      container.invalidate(memberMembershipsProvider(scope));
      await tester.pumpAndSettle();
      expect(find.text('No outstanding memberships remain.'), findsOneWidget);
      expect(find.text('Choose membership to pay'), findsOneWidget);
      expect(selectorContent(find.byType(ListTile)), findsNothing);
      expect(find.byType(RecordPaymentSheet), findsNothing);
      expect(payments.collections, isEmpty);
      await tester.tap(find.byTooltip('Close membership selection'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Collect payment'), findsNothing);
    },
  );

  for (final status in ['upcoming', 'expired']) {
    testWidgets(
      'payment form uses $status lifecycle label without changing eligibility',
      (tester) async {
        await mount(tester);
        members.debts[memberId] = [
          debtJson(status: status == 'upcoming' ? 'active' : 'expired')
            ..addAll({
              'isCurrentlyActive': false,
              'startDate': status == 'upcoming' ? '2027-01-01' : '2025-01-01',
              'endDate': status == 'upcoming' ? '2027-01-31' : '2025-01-31',
            }),
        ];
        container
            .read(appRouterProvider)
            .go(
              '${AppRoutes.members}/$memberId/membership/$subscriptionId?gymId=$gymA',
            );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Record Payment'));
        await tester.tap(find.text('Record Payment'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(RecordPaymentSheet),
            matching: find.text(
              status == 'upcoming'
                  ? 'Membership: Upcoming'
                  : 'Membership: Expired',
            ),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('collection-amount')))
              .enabled,
          isTrue,
        );
        expect(find.text('Membership: active'), findsNothing);
        expect(payments.collections, isEmpty);
      },
    );
  }

  for (final mode in ['paid', 'cancelled', 'unverified']) {
    testWidgets('Pay Now hidden for $mode balances and does not invent zero', (
      tester,
    ) async {
      await mount(tester);
      final record = debtJson(
        balance: mode == 'paid' ? 0 : 50000,
        status: mode == 'cancelled' ? 'cancelled' : 'active',
      );
      if (mode == 'unverified') record.remove('paymentSummary');
      members.debts[memberId] = [record];
      await showMemberDetails(tester);
      await reveal(tester, find.text('Membership & payments'));
      expect(find.text('Collect payment'), findsNothing);
      expect(find.byType(RecordPaymentSheet), findsNothing);
      expect(payments.collections, isEmpty);
      if (mode == 'unverified') {
        expect(
          find.textContaining('Membership balances could not be verified'),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.text('Retry'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
          findsWidgets,
        );
      }
    });
  }

  testWidgets(
    'a gym switch while choosing unpaid memberships blocks cross-scope payment',
    (tester) async {
      await mount(tester);
      members.debts[memberId]!.add(debtJson(id: gymB, status: 'expired'));
      await showMemberDetails(tester);
      await reveal(tester, find.text('Collect payment'));
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      expect(find.text('Choose membership to pay'), findsOneWidget);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Membership balances are unavailable'),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('pay-membership-$gymB')), findsNothing);
      expect(find.byType(RecordPaymentSheet), findsNothing);
      expect(payments.collections, isEmpty);
    },
  );
  testWidgets(
    'Pay Now reads later history pages rather than hiding existing debt',
    (tester) async {
      await mount(tester);
      members.debts[memberId] = [
        for (var index = 0; index < 20; index++)
          debtJson(
            id: (100 + index).toRadixString(16).padLeft(24, '0'),
            balance: 0,
            status: 'expired',
          ),
        debtJson(id: gymB, balance: 70000, status: 'expired'),
      ];
      await showMemberDetails(tester);
      await reveal(tester, find.text('Collect payment'));
      expect(members.operations, contains('memberships:$gymA:$memberId:2'));
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RecordPaymentSheet>(find.byType(RecordPaymentSheet))
            .scope
            .subscriptionId,
        gymB,
      );
    },
  );
  testWidgets(
    'Pay Now confirmed installment refreshes member, history, dues and dashboard',
    (tester) async {
      await mount(tester);
      final gym = container.read(adminGymProvider)!;
      final scope = scopeFor(gym, memberId);
      final dashboard =
          container.read(dashboardRepositoryProvider)
              as FakeDashboardRepository;
      final before = dashboard.requests.length;
      container.listen(outstandingDuesProvider, (_, _) {});
      await container.read(outstandingDuesProvider.future);
      await showMemberDetails(tester);
      await reveal(tester, find.text('Collect payment'));
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await confirm(tester);
      expect(payments.collections, hasLength(1));
      expect(
        container
            .read(memberMembershipsProvider(scope))
            .asData!
            .value!
            .single
            .payments!
            .balancePaise,
        40000,
      );
      expect(
        (await container.read(outstandingDuesProvider.future))!.totalPaise,
        40000,
      );
      expect(dashboard.requests.length, greaterThan(before));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberDetailsPage), findsOneWidget);
      expect(payments.collections, hasLength(1));
    },
  );
  for (final input in ['', '0', '-1', '500.01', '1.234']) {
    testWidgets('invalid collection amount "$input" sends no POST', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('collection-amount')), input);
      await confirm(tester);
      expect(payments.collections, isEmpty);
    });
  }
  for (final method in [
    PaymentMethod.upi,
    PaymentMethod.bankTransfer,
    PaymentMethod.card,
  ]) {
    testWidgets('${method.label} requires a reference', (tester) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(method.label).last);
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(find.text('A payment reference is required.'), findsOneWidget);
      expect(payments.collections, isEmpty);
    });
  }
  testWidgets(
    'cash without reference records real confirmation and refreshes dues',
    (tester) async {
      await openForm(tester);
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await confirm(tester);
      expect(payments.collections.single.body['amountPaise'], 10000);
      expect(
        payments.collections.single.body.containsKey('transactionReference'),
        isFalse,
      );
      expect(find.text('Payment recorded'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RecordPaymentSheet),
          matching: find.text('Remaining balance: ₹400.00'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      container
          .read(appRouterProvider)
          .go('${AppRoutes.outstandingDues}?gymId=$gymA');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Total current dues'));
      expect(find.text('₹400.00'), findsOneWidget);
    },
  );
  testWidgets(
    'ambiguous collection is preserved across form reopening and exact retry',
    (tester) async {
      await openForm(tester);
      payments.failure = const BillingFailure(
        'Network interrupted',
        uncertain: true,
      );
      await tester.enterText(find.byKey(const Key('collection-amount')), '100');
      await confirm(tester);
      final saved = payments.collections.single;
      expect(find.text('Retry saved payment'), findsOneWidget);
      await tester.ensureVisible(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Review saved payment'));
      await tester.tap(find.text('Review saved payment'));
      await tester.pumpAndSettle();
      payments.failure = null;
      await tester.ensureVisible(find.text('Retry saved payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry saved payment'));
      await tester.pumpAndSettle();
      expect(payments.collections.last.frozenJson, saved.frozenJson);
      expect(payments.collections.last.key, saved.key);
      expect(find.text('Payment recorded'), findsOneWidget);
    },
  );
  testWidgets('duplicate taps while in flight submit only one payment', (
    tester,
  ) async {
    await openForm(tester);
    payments.gate = Completer<RecordedPayment>();
    await tester.enterText(find.byKey(const Key('collection-amount')), '100');
    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm payment'));
    await tester.tap(find.text('Confirm payment'));
    await tester.pump();
    expect(payments.collections, hasLength(1));
    payments.gate!.complete(payments.confirmation(payments.collections.single));
    await tester.pumpAndSettle();
    expect(find.text('Payment recorded'), findsOneWidget);
  });
  testWidgets('scope change closes old collection workflow without a POST', (
    tester,
  ) async {
    await openForm(tester);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The account or gym changed. Close this form and reopen the correct membership.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirm payment'), findsNothing);
    expect(payments.collections, isEmpty);
  });
  testWidgets('revenue empty/error retry and dues failure stay explicit', (
    tester,
  ) async {
    await mount(tester);
    payments.empty = true;
    await tapCard(tester, 'Total Revenue');
    expect(find.text('No payments during this period.'), findsOneWidget);
    expect(find.text('₹0.00'), findsOneWidget);
    payments.failure = const BillingFailure('Payment service unavailable');
    await tester.tap(find.byTooltip('Refresh revenue'));
    await tester.pumpAndSettle();
    expect(find.text('Payment service unavailable'), findsOneWidget);
    payments.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to dashboard'));
    await tester.pumpAndSettle();
    members.failure = const BillingFailure('Balances unavailable');
    await tapCard(tester, 'Pending Amount');
    expect(find.text('Balances unavailable'), findsOneWidget);
    members.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('₹500.00'), findsOneWidget);
  });
  testWidgets(
    'metric card exposes a button semantic and reacts to whole-card tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      final card = find.byWidgetPredicate(
        (widget) =>
            widget is CircularMetricCard && widget.title == 'Total Revenue',
      );
      if (card.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(card);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      await tester.tapAt(tester.getBottomRight(card) - const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(find.text('Revenue Details'), findsOneWidget);
      semantics.dispose();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'dues and collection adapt to 320px and enlarged text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await openForm(tester);
        await tester.ensureVisible(find.byKey(const Key('collection-amount')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('collection-amount')),
          '100',
        );
        await confirm(tester);
        expect(find.text('Payment recorded'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'plan error retains independent retry and whole-card navigation',
    (tester) async {
      await mount(tester);
      plans.failure = const BillingFailure('Plans temporarily unavailable');
      container.invalidate(activePlanCountProvider);
      await tester.pumpAndSettle();
      final retry = find.text('Retry plans');
      if (retry.evaluate().isEmpty) await tester.scrollUntilVisible(retry, 200);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      plans.failure = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppRoutes.dashboard,
      );
      plans.failure = const BillingFailure('Plans temporarily unavailable');
      container.invalidate(activePlanCountProvider);
      await tester.pumpAndSettle();
      await tapCard(tester, 'Active Plans');
      expect(container.read(appRouterProvider).state.uri.path, AppRoutes.plans);
    },
  );

  testWidgets('full-payment recovery stays reachable when server balance is zero', (
    tester,
  ) async {
    final storage = TestOnboardingStorage();
    final recoveryScope = PaymentRecoveryScope.fromConfig(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.invalid/api/v1/'),
      userId: 'test-account',
      gymId: gymA,
      memberId: memberId,
      subscriptionId: subscriptionId,
    );
    final frozen = PendingPayment(
      scope: recoveryScope,
      createdAt: DateTime.utc(2026),
      collection: PaymentCollection(
        memberId: memberId,
        subscriptionId: subscriptionId,
        key: 'restored-full-payment',
        payment: ManualPayment(
          amountPaise: 50000,
          method: PaymentMethod.cash,
          paidAt: DateTime.utc(2026),
        ),
      ),
    );
    final unresolved = frozen.advance([
      PaymentAttempt(PaymentAttemptOutcome.unresolved),
    ]);
    storage.values[recoveryScope.storageKey] = unresolved.encode();
    await mount(tester, recoveryStorage: storage);
    members.debts[memberId] = [debtJson(balance: 0)];
    container
        .read(appRouterProvider)
        .go(
          '${AppRoutes.members}/$memberId/membership/$subscriptionId?gymId=$gymA',
        );
    await tester.pumpAndSettle();
    expect(find.text('Review saved payment'), findsOneWidget);
    expect(find.text('Record Payment'), findsNothing);
    await Scrollable.ensureVisible(
      tester.element(find.text('Review saved payment')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review saved payment'));
    await tester.pumpAndSettle();
    expect(find.text('Saved payment awaiting confirmation'), findsOneWidget);
    expect(find.text('Amount: ₹500.00'), findsOneWidget);
    expect(find.text('Retry saved payment'), findsOneWidget);
    expect(payments.collections, isEmpty);
    await Scrollable.ensureVisible(
      tester.element(find.text('Retry saved payment')),
    );
    await tester.pumpAndSettle();
    // Simulate exact backend replay; this fake must not apply a second installment.
    payments.onCollection = null;
    await tester.tap(find.text('Retry saved payment'));
    await tester.pumpAndSettle();
    expect(payments.collections.single.key, frozen.collection.key);
    expect(
      payments.collections.single.frozenJson,
      frozen.collection.frozenJson,
    );
    expect(find.text('Payment recorded'), findsOneWidget);
    expect(storage.values[recoveryScope.storageKey], isNotNull);
    await Scrollable.ensureVisible(tester.element(find.text('Done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(storage.values[recoveryScope.storageKey], isNull);
    expect(find.text('Review saved payment'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'dues duplicate names retain distinct codes at 320dp and large text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await mount(tester);
        members.profiles.add(
          MemberProfile.fromJson({
            ...profileJson(),
            'id': gymB,
            'memberCode': 'ME02',
          }),
        );
        members.debts[gymB] = [
          debtJson(
            id: '000000000000000000000024',
            balance: 70000,
            status: 'expired',
          ),
        ];
        await tapCard(tester, 'Pending Amount');
        for (final code in ['ME01', 'ME02']) {
          await reveal(tester, find.text('Member code: $code'));
          expect(find.text('Member code: $code').hitTestable(), findsOneWidget);
          final semantics = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label?.contains('Member code: $code.') ==
                    true,
          );
          expect(semantics, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.text('Member code: ME02'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MemberDetailsPage>(find.byType(MemberDetailsPage))
              .memberId,
          gymB,
        );
        expect(payments.collections, isEmpty);
      },
    );
  }

  testWidgets(
    'dues shows upcoming saved dates with a singular membership count',
    (tester) async {
      await mount(tester);
      members.debts[memberId] = [
        debtJson()..addAll({
          'isCurrentlyActive': false,
          'startDate': '2027-01-01',
          'endDate': '2027-01-31',
        }),
      ];
      await tapCard(tester, 'Pending Amount');
      expect(find.text('Total across 1 unpaid membership'), findsOneWidget);
      expect(find.text('Upcoming membership dates'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('₹500 due'), findsOneWidget);
      expect(payments.collections, isEmpty);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'selector header and Close stay reachable with long plans at 320dp and double text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await mount(tester);
        members.debts[memberId] = [
          debtJson()
            ..['planNameSnapshot'] =
                'Complete strength and conditioning with personal training',
          debtJson(id: gymB, status: 'expired')
            ..['planNameSnapshot'] =
                'Previous strength and conditioning membership with weekend gym access',
        ];
        await showMemberDetails(tester);
        await reveal(tester, find.text('Collect payment'));
        await tester.tap(find.text('Collect payment'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(ValueKey('pay-membership-$gymB')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Choose membership to pay').hitTestable(),
          findsOneWidget,
        );
        final close = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Close membership selection',
        );
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(payments.collections, isEmpty);
      },
    );
  }
}
