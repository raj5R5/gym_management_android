import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'photo_fakes.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/soft_panel.dart';
import 'package:gym_management_app/shared/widgets/profile_section.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/presentation/member_details_activity.dart';
import 'package:gym_management_app/features/members/presentation/member_details_cards.dart';
import 'package:gym_management_app/features/members/presentation/member_details_financial_cards.dart';
import 'package:gym_management_app/features/members/presentation/member_details_page.dart';
import 'package:gym_management_app/features/members/presentation/member_form_page.dart';
import 'package:gym_management_app/features/members/presentation/member_list_widgets.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/presentation/purchase_page.dart';
import 'package:gym_management_app/features/memberships/presentation/membership_page.dart';
import 'package:gym_management_app/features/memberships/presentation/membership_detail_page.dart';
import 'package:gym_management_app/features/memberships/presentation/record_payment_sheet.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/members/providers/member_overview_providers.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../memberships/billing_fakes.dart';
import '../memberships/payment_fakes.dart';
import 'member_fakes.dart';
import 'onboarding_fakes.dart' show TestOnboardingStorage;

class DetailsFake extends DueMembersFake {
  Map<String, dynamic> memberFields = profileJson();
  Completer<MemberSummary>? summaryGate;
  Object? summaryFailure;
  Object? historyFailure;
  @override
  Future<MemberSummary> summary(String gymId, String id) async {
    operations.add('summary:$gymId:$id');
    if (summaryFailure != null) throw summaryFailure!;
    if (summaryGate != null) return summaryGate!.future;
    final all = debts[id.toLowerCase()] ?? [];
    final current = all
        .where(
          (row) =>
              row['status'] == 'active' && row['isCurrentlyActive'] == true,
        )
        .firstOrNull;
    final money = current?['paymentSummary'] as Map?;
    final json = summaryJson(populated: true)
      ..addAll({
        'member': {...memberFields, 'id': id.toLowerCase()},
        'currentSubscription': current,
        'currentSubscriptionPaymentSummary': money == null
            ? null
            : {
                'pricePaise': current!['pricePaiseSnapshot'],
                'paidAmountPaise': money['totalSuccessfulPaidPaise'],
                'remainingAmountPaise': money['remainingBalancePaise'],
                'paymentCount': 1,
              },
        'subscriptionHistory': {
          'items': all.take(20).toList(),
          'page': 1,
          'limit': 20,
          'total': all.length,
        },
      });
    if (all.every((row) => row['paymentSummary'] != null)) {
      json['paymentSummary'] = {
        'totalSuccessfulAmountPaise': all.fold<int>(
          0,
          (total, row) =>
              total +
              (row['paymentSummary']['totalSuccessfulPaidPaise'] as int),
        ),
        'successfulPaymentCount': all.length,
        'latestSuccessfulPayment': null,
      };
    }
    return MemberSummary.fromJson(json);
  }

  @override
  Future<MembershipHistory> memberships(
    String gymId,
    String id,
    int page,
  ) async {
    if (historyFailure != null) throw historyFailure!;
    if (historyGate != null) return historyGate!.future;
    return super.memberships(gymId, id.toLowerCase(), page);
  }
}

void main() {
  late DetailsFake members;
  late FakePaymentRepository payments;
  late ProviderContainer container;
  Future<void> mount(
    WidgetTester tester, {
    bool details = true,
    TestOnboardingStorage? recoveryStorage,
    FakeDashboardRepository? dashboard,
  }) async {
    payments = FakePaymentRepository()..onCollection = members.collect;
    members.profiles = [MemberProfile.fromJson(members.memberFields)];
    container = ProviderContainer(
      overrides: [
        memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
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
          dashboard ?? FakeDashboardRepository(),
        ),
        memberRepositoryProvider.overrideWithValue(members),
        // The members list sits under member details; keep it off the network.
        memberOverviewRepositoryProvider.overrideWithValue(
          FakeMemberOverviewRepository(members),
        ),
        membershipRepositoryProvider.overrideWithValue(
          FakeMembershipRepository(),
        ),
        paymentRepositoryProvider.overrideWithValue(payments),
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: recoveryStorage ?? TestOnboardingStorage(),
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
    if (details) {
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$memberId?gymId=$gymA');
    }
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    if (target.evaluate().isEmpty) {
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 180, scrollable: scroll);
      }
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
  }

  Finder currentCard() => find.byType(MemberCurrentMembershipCard);

  /// Membership history starts collapsed, like the other secondary sections.
  Future<void> openHistory(WidgetTester tester) async {
    await reveal(tester, find.text('Membership history'));
    await tester.tap(find.text('Membership history'));
    await tester.pumpAndSettle();
  }

  Finder financeCard() => find.byType(MemberPaymentSummaryCard);
  setUp(() => members = DetailsFake());

  for (final zone in ['Asia/Kolkata', 'UTC']) {
    testWidgets('overview passes gym timezone $zone to latest payment', (
      tester,
    ) async {
      final json = dashboardJson();
      (json['period'] as Map)['timezone'] = zone;
      final dashboard = FakeDashboardRepository()
        ..result = GymDashboard.fromJson(json);
      await mount(tester, dashboard: dashboard);
      await reveal(tester, find.textContaining('Total paid'));
      expect(
        tester
            .widget<MemberLatestPayment>(find.byType(MemberLatestPayment))
            .timezone,
        zone,
      );
    });
  }

  testWidgets('latest payment rejects stale timezone metadata during refresh', (
    tester,
  ) async {
    final dashboard = FakeDashboardRepository();
    await mount(tester, dashboard: dashboard);
    await reveal(tester, find.textContaining('Total paid'));
    String? displayedZone() => tester
        .widget<MemberLatestPayment>(find.byType(MemberLatestPayment))
        .timezone;
    expect(displayedZone(), 'Asia/Kolkata');

    dashboard.gate = Completer<GymDashboard>();
    container.invalidate(dashboardProvider);
    await tester.pump();
    expect(displayedZone(), isNull);

    dashboard.gate!.completeError(StateError('Timezone metadata unavailable'));
    await tester.pumpAndSettle();
    expect(displayedZone(), isNull);

    dashboard.gate = null;
    final json = dashboardJson();
    (json['period'] as Map)['timezone'] = 'UTC';
    dashboard.result = GymDashboard.fromJson(json);
    container.invalidate(dashboardProvider);
    await tester.pumpAndSettle();
    expect(displayedZone(), 'UTC');
  });

  testWidgets(
    'owner overview puts identity, membership and money before secondary details',
    (tester) async {
      await mount(tester);
      final rows =
          tester
                  .widget<ListView>(
                    find
                        .descendant(
                          of: find.byType(MemberDetailsPage),
                          matching: find.byType(ListView),
                        )
                        .last,
                  )
                  .childrenDelegate
              as SliverChildListDelegate;
      final types = rows.children.map((widget) => widget.runtimeType).toList();
      final moneyCard = rows.children.indexWhere(
        (widget) => widget.key == const ValueKey('member-money-card'),
      );
      // Who, then where they stand, then the money, then activity, then details.
      expect(
        types.indexOf(MemberProfileCard),
        lessThan(types.indexOf(MemberStatusLine)),
      );
      expect(types.indexOf(MemberStatusLine), lessThan(moneyCard));
      expect(moneyCard, lessThan(types.indexOf(MemberActivityList)));
      expect(
        types.indexOf(MemberActivityList),
        lessThan(types.indexOf(MemberPersonalDetails)),
      );
      // Plan first, then what is owed, inside the one card.
      expect(
        tester.getTopLeft(currentCard()).dy,
        lessThan(tester.getTopLeft(financeCard()).dy),
      );
      await reveal(tester, find.text('Contact & personal details'));
      expect(find.text('Phone'), findsNothing);
      await tester.tap(find.text('Contact & personal details'));
      await tester.pumpAndSettle();
      expect(find.text('Phone'), findsOneWidget);
    },
  );

  testWidgets(
    'expired with dues explains renewal separately from collectible debt',
    (tester) async {
      members.debts[memberId] = [debtJson(status: 'expired')];
      await mount(tester);
      // The status line says it first; the membership card says it again.
      final expired = find.descendant(
        of: currentCard(),
        matching: find.text('Membership expired'),
      );
      await reveal(tester, expired);
      expect(
        find.descendant(
          of: find.byType(MemberStatusLine),
          matching: find.text('₹500.00 due'),
        ),
        findsOneWidget,
      );
      expect(find.text('No current membership'), findsOneWidget);
      await reveal(tester, find.text('Collect payment'));
      expect(
        find.descendant(of: financeCard(), matching: find.text('₹500.00')),
        findsOneWidget,
      );
      expect(find.textContaining('including expired plans'), findsOneWidget);
      expect(payments.collections, isEmpty);
    },
  );

  testWidgets('suspended profile is distinct from an active paid membership', (
    tester,
  ) async {
    members.memberFields['status'] = 'suspended';
    members.debts[memberId] = [debtJson(balance: 0)];
    await mount(tester);
    expect(find.text('Suspended'), findsOneWidget);
    expect(
      tester.widget<MemberStatusBadge>(find.byType(MemberStatusBadge)).status,
      MemberStatus.suspended,
    );
    await reveal(tester, find.text('Fully Paid'));
    expect(find.text('Membership: Active'), findsOneWidget);
    await reveal(tester, find.text('To collect'));
    expect(find.text('Collect payment'), findsNothing);
    expect(find.text('No outstanding dues.'), findsOneWidget);
  });

  testWidgets('paid current plan does not hide debt from an expired plan', (
    tester,
  ) async {
    members.debts[memberId] = [
      debtJson(balance: 0),
      debtJson(id: gymB, balance: 70000, status: 'expired')
        ..['planNameSnapshot'] = 'Older plan',
    ];
    await mount(tester);
    // The top line never hides older debt behind a paid current plan.
    expect(
      find.descendant(
        of: find.byType(MemberStatusLine),
        matching: find.text('₹700.00 due'),
      ),
      findsOneWidget,
    );
    await reveal(tester, find.text('Fully Paid'));
    expect(
      find.descendant(of: currentCard(), matching: find.text('Fully Paid')),
      findsOneWidget,
    );
    expect(find.textContaining('from older plans'), findsOneWidget);
    await reveal(tester, find.text('Collect payment'));
    expect(
      find.descendant(of: financeCard(), matching: find.text('₹700.00')),
      findsOneWidget,
    );
    expect(payments.collections, isEmpty);
  });

  testWidgets(
    'profile uses initials, actual optional fields and a working compact edit action',
    (tester) async {
      members.memberFields.addAll({
        'dateOfBirth': '2000-10-12',
        'gender': 'prefer_not_to_say',
        'address': {
          'line1': '12 Main Street',
          'city': 'Pune',
          'countryCode': 'IN',
          'state': 'Maharashtra',
          'postalCode': '411001',
        },
        'emergencyContact': {
          'name': 'Sam River',
          'phone': '9876543222',
          'relationship': 'Sibling',
        },
      });
      await mount(tester);
      expect(
        tester
            .widget<MemberProfileCard>(find.byType(MemberProfileCard))
            .member
            .phone,
        '+91 9876543210',
      );
      expect(find.text('AR'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.text('Member code: ME01'), findsOneWidget);
      expect(find.byType(MemberStatusBadge), findsOneWidget);
      await reveal(tester, find.text('Contact & personal details'));
      await tester.tap(find.text('Contact & personal details'));
      await tester.pumpAndSettle();
      expect(find.text('Oct 12, 2000'), findsOneWidget);
      expect(find.text('Prefer Not To Say'), findsOneWidget);
      expect(find.textContaining('12 Main Street'), findsOneWidget);
      await reveal(tester, find.text('Emergency contact'));
      expect(find.text('Sam River'), findsOneWidget);
      expect(find.text('9876543222'), findsOneWidget);
      await reveal(tester, find.text('Edit member'));
      await tester.tap(find.text('Edit member'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MemberFormPage>(find.byType(MemberFormPage)).memberId,
        memberId,
      );
    },
  );
  testWidgets(
    'missing optional profile data stays absent and parked Attendance is not exposed',
    (tester) async {
      await mount(tester);
      expect(find.text('Date of birth'), findsNothing);
      expect(find.text('Gender'), findsNothing);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Address'), findsNothing);
      await reveal(tester, find.text('Assigned trainers'));
      await tester.tap(find.text('Assigned trainers'));
      await tester.pumpAndSettle();
      expect(find.text('Central (active)'), findsNothing);
      expect(find.textContaining('Pat Lee'), findsOneWidget);
      expect(find.text('Emergency contact'), findsNothing);
      expect(find.text('Attendance'), findsNothing);
      expect(find.textContaining(memberId), findsNothing);
      expect(find.textContaining(gymA), findsNothing);
      expect(find.textContaining(gymB), findsNothing);
    },
  );
  testWidgets('current membership shows the plan, its dates and what is paid', (
    tester,
  ) async {
    await mount(tester);
    await reveal(tester, find.text('Current membership'));
    final card = currentCard();
    expect(
      find.descendant(of: card, matching: find.text('Monthly')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('1 Mar 2026 –')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('31 Mar 2026')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('₹1,000.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('₹1,500.00')),
      findsOneWidget,
    );
    // The plan's dates are past, so no time left or progress is invented.
    expect(find.textContaining('days left'), findsNothing);
    expect(
      find.descendant(of: card, matching: find.byType(LinearProgressIndicator)),
      findsNothing,
    );
    // What is owed is shown once, beside the collection action.
    expect(
      find.descendant(of: financeCard(), matching: find.text('₹500.00')),
      findsOneWidget,
    );
    expect(find.text('Purchase membership'), findsNothing);
    await reveal(tester, find.byKey(const ValueKey('member-payments-row')));
    await tester.tap(find.byKey(const ValueKey('member-payments-row')));
    await tester.pumpAndSettle();
    expect(find.byType(MembershipPage), findsOneWidget);
    expect(
      tester.widget<MembershipPage>(find.byType(MembershipPage)).memberId,
      memberId,
    );
  });
  testWidgets('a running plan shows the days left and the time used', (
    tester,
  ) async {
    // 1–31 Mar (end exclusive); on 21 Mar ten days remain of thirty.
    final membership = Membership.fromJson(debtJson());
    Future<void> show(DateTime today) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MembershipAtAGlance(membership: membership, today: today),
        ),
      ),
    );
    await show(DateTime(2026, 3, 21));
    expect(find.text('10 days left'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(20 / 30, .001));

    await show(DateTime(2026, 2, 20));
    expect(find.text('Starts in 9 days'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('current membership uses the saved subscription snapshot', (
    tester,
  ) async {
    members.debts[memberId] = [
      debtJson()..addAll({
        'planNameSnapshot': 'Monthly legacy offer',
        'durationDaysSnapshot': 95,
        'startDate': '2026-01-01',
        'endDate': '2026-04-06',
      }),
    ];
    await mount(tester);
    await reveal(tester, find.text('Current membership'));
    for (final value in [
      'Monthly legacy offer',
      '1 Jan 2026 –',
      '6 Apr 2026',
      '₹1,000.00',
      '₹1,500.00',
    ]) {
      expect(
        find.descendant(of: currentCard(), matching: find.text(value)),
        findsOneWidget,
        reason: value,
      );
    }
    expect(members.writes, isEmpty);
    expect(payments.collections, isEmpty);
  });
  for (final status in ['expired', 'cancelled']) {
    testWidgets(
      '$status history never appears as current and respects purchase/payment eligibility',
      (tester) async {
        members.debts[memberId] = [debtJson(status: status)];
        await mount(tester);
        await reveal(tester, find.text('No current membership'));
        expect(
          find.descendant(of: currentCard(), matching: find.text('Monthly')),
          findsNothing,
        );
        expect(find.text('Purchase membership'), findsOneWidget);
        await reveal(tester, financeCard());
        if (status == 'expired') {
          expect(find.text('Collect payment'), findsOneWidget);
        } else {
          expect(find.text('Collect payment'), findsNothing);
          expect(find.text('Previous membership cancelled'), findsOneWidget);
        }
        await openHistory(tester);
        expect(
          find.text(
            'Membership: ${status == 'expired' ? 'Expired' : 'Cancelled'}',
          ),
          findsOneWidget,
        );
        await reveal(tester, find.byTooltip('Open membership actions'));
        await tester.tap(find.byTooltip('Open membership actions'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MembershipDetailPage>(find.byType(MembershipDetailPage))
              .subscriptionId,
          subscriptionId,
        );
      },
    );
  }
  testWidgets(
    'upcoming saved plan is clearly distinguished from current and blocks purchase',
    (tester) async {
      members.debts[memberId] = [
        debtJson()..addAll({
          'isCurrentlyActive': false,
          'startDate': '2027-01-01',
          'endDate': '2027-01-31',
        }),
      ];
      await mount(tester);
      await reveal(tester, find.text('No current membership'));
      expect(find.textContaining('upcoming membership'), findsOneWidget);
      expect(
        find.descendant(
          of: currentCard(),
          matching: find.text('Membership: Upcoming'),
        ),
        findsOneWidget,
      );
      expect(find.text('Purchase membership'), findsNothing);
      expect(
        find.descendant(of: currentCard(), matching: find.text('1 Jan 2027 –')),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
  testWidgets(
    'empty membership offers the existing purchase route without creating any records',
    (tester) async {
      members.debts[memberId] = [];
      await mount(tester);
      await reveal(tester, find.text('Purchase membership'));
      await tester.tap(find.text('Purchase membership'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PurchasePage>(find.byType(PurchasePage)).memberId,
        memberId,
      );
      expect(payments.collections, isEmpty);
      expect(members.writes, isEmpty);
    },
  );
  testWidgets('zero balance uses positive styling and hides Pay Now', (
    tester,
  ) async {
    members.debts[memberId] = [debtJson(balance: 0)];
    await mount(tester);
    await reveal(tester, find.text('Fully Paid'));
    expect(
      tester
          .widget<StatusPill>(find.widgetWithText(StatusPill, 'Fully Paid'))
          .tone,
      AppTone.positive,
    );
    await reveal(tester, financeCard());
    expect(find.text('Collect payment'), findsNothing);
    expect(
      find.descendant(of: financeCard(), matching: find.text('₹0.00')),
      findsOneWidget,
    );
  });
  testWidgets(
    'unavailable balance stays unavailable, offers retry and never authorizes payment',
    (tester) async {
      members.debts[memberId]!.single.remove('paymentSummary');
      await mount(tester);
      await reveal(tester, financeCard());
      expect(
        find.descendant(of: financeCard(), matching: find.text('Unavailable')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: financeCard(), matching: find.text('₹0.00')),
        findsNothing,
      );
      expect(find.text('Collect payment'), findsNothing);
      expect(
        find.textContaining('balances could not be verified'),
        findsOneWidget,
      );
      expect(payments.collections, isEmpty);
    },
  );
  testWidgets(
    'payment summary totals saved debts without combining payment requests',
    (tester) async {
      members.debts[memberId] = [
        debtJson(),
        debtJson(id: gymB, balance: 70000, status: 'expired')
          ..['planNameSnapshot'] = 'Previous plan',
      ];
      await mount(tester);
      await reveal(tester, financeCard());
      expect(
        find.descendant(of: financeCard(), matching: find.text('₹1,200.00')),
        findsOneWidget,
      );
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      expect(find.text('Choose membership to pay'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('pay-membership-$gymB')));
      await tester.pumpAndSettle();
      final sheet = tester.widget<RecordPaymentSheet>(
        find.byType(RecordPaymentSheet),
      );
      expect(sheet.scope.subscriptionId, gymB);
      expect(sheet.memberName, 'Alex River');
      expect(sheet.memberCode, 'ME01');
      expect(payments.collections, isEmpty);
    },
  );

  testWidgets(
    'a missing latest record does not contradict the saved successful payment count',
    (tester) async {
      await mount(tester);
      await reveal(tester, find.byKey(const ValueKey('member-payments-row')));
      expect(
        find.text('Latest payment details unavailable. Open payment history.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: financeCard(),
          matching: find.text('No successful payments.'),
        ),
        findsNothing,
      );
    },
  );
  testWidgets(
    'member overview hides raw gym IDs but retains real selector values and switching',
    (tester) async {
      await mount(tester);
      final selector = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(selector.initialValue, gymA);
      expect(find.textContaining(gymA), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gym 2').last);
      await tester.pumpAndSettle();
      expect(container.read(adminGymProvider)!.gymId, gymB);
      expect(find.text('Alex River'), findsNothing);
      expect(find.textContaining('gym context changed'), findsOneWidget);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'amount tiles use pale semantic dues color with readable large text in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            home: const Scaffold(
              body: MemberAmounts(paidPaise: 100000, balancePaise: 50000),
            ),
          ),
        );
        final amount = tester.widget<Text>(find.text('₹500.00'));
        final panel = tester.widget<SoftPanel>(
          find.ancestor(
            of: find.text('₹500.00'),
            matching: find.byType(SoftPanel),
          ),
        );
        expect(panel.backgroundColor, PendingColors.surfaceFor(brightness));
        final a = amount.style!.color!.computeLuminance(),
            b = panel.backgroundColor!.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
          greaterThanOrEqualTo(3),
        );
        expect(amount.style!.fontSize, greaterThanOrEqualTo(19));
        expect(amount.style!.fontWeight, FontWeight.w700);
      },
    );
  }

  testWidgets(
    'initial loading and retry never show invented profile or zero amounts',
    (tester) async {
      members.summaryGate = Completer<MemberSummary>();
      members.debts[memberId] = [];
      await mount(tester, details: false);
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$memberId?gymId=$gymA');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(MemberProfileCard), findsNothing);
      members.summaryGate!.complete(MemberSummary.fromJson(summaryJson()));
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsOneWidget);
    },
  );
  testWidgets(
    'initial profile failure has a working retry and no fabricated fields',
    (tester) async {
      members.summaryFailure = const MemberFailure(
        'Member unavailable. Try again.',
      );
      await mount(tester);
      expect(find.text('Member unavailable. Try again.'), findsOneWidget);
      expect(find.byType(MemberProfileCard), findsNothing);
      members.summaryFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsOneWidget);
    },
  );
  testWidgets(
    'case-normalized backend member IDs still render for valid uppercase deep links',
    (tester) async {
      // Use a letter-bearing ObjectId to exercise real canonicalization.
      final id = 'abcdefabcdefabcdefabcdef';
      members.memberFields['id'] = id;
      members.debts[id] = [];
      await mount(tester, details: false);
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/${id.toUpperCase()}?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsOneWidget);
      expect(
        tester
            .widget<MemberProfileCard>(find.byType(MemberProfileCard))
            .member
            .id,
        id,
      );
    },
  );

  testWidgets(
    'membership history pagination replaces the old page and keeps the correct subscription action',
    (tester) async {
      members.debts[memberId] = [
        for (var index = 0; index < 21; index++)
          debtJson(
            id: (200 + index).toRadixString(16).padLeft(24, '0'),
            status: 'expired',
          )..['planNameSnapshot'] = 'Past plan $index',
      ];
      await mount(tester);
      await openHistory(tester);
      final next = find.byTooltip('Next page');
      await tester.scrollUntilVisible(
        next,
        200,
        maxScrolls: 100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await reveal(tester, next);
      expect(next.hitTestable(), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Past plan 20'));
      expect(find.text('Past plan 0'), findsNothing);
      expect(find.text('Page 2 · 21 total'), findsOneWidget);
      await reveal(tester, find.byTooltip('Open membership actions'));
      await tester.tap(find.byTooltip('Open membership actions'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MembershipDetailPage>(find.byType(MembershipDetailPage))
            .subscriptionId,
        (220).toRadixString(16).padLeft(24, '0'),
      );
    },
  );
  testWidgets(
    'failed history refresh retains its snapshot and disables stale actions until retry succeeds',
    (tester) async {
      await mount(tester);
      await openHistory(tester);
      await reveal(tester, find.text('View membership details'));
      final scope = scopeFor(container.read(adminGymProvider)!, memberId);
      members.historyFailure = const MemberFailure('History refresh failed.');
      container.invalidate(memberHistoryProvider((scope: scope, page: 1)));
      await tester.pumpAndSettle();
      final history = find.widgetWithText(
        MemberDetailsDisclosure,
        'Membership history',
      );
      expect(
        find.descendant(of: history, matching: find.text('Monthly')),
        findsOneWidget,
      );
      expect(find.text('History refresh failed.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'View membership details'),
            )
            .onPressed,
        isNull,
      );
      members.historyFailure = null;
      final retry = find.descendant(
        of: history,
        matching: find.ancestor(
          of: find.text('Retry'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      );
      await reveal(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('History refresh failed.'), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'View membership details'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('payment history link preserves the correct member and gym', (
    tester,
  ) async {
    await mount(tester);
    await reveal(tester, find.byKey(const ValueKey('member-payments-row')));
    await tester.tap(find.byKey(const ValueKey('member-payments-row')));
    await tester.pumpAndSettle();
    final page = tester.widget<MembershipPage>(find.byType(MembershipPage));
    expect(page.memberId, memberId);
    expect(page.gymId, gymA);
  });
  testWidgets(
    'profile survives a failed same-scope refresh with clear retry feedback',
    (tester) async {
      await mount(tester);
      members.summaryFailure = const MemberFailure('Profile refresh failed.');
      await tester.tap(find.byTooltip('Refresh member details'));
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsOneWidget);
      expect(find.text('Profile refresh failed.'), findsOneWidget);
      expect(find.textContaining('last verified'), findsWidgets);
      members.summaryFailure = null;
      await reveal(
        tester,
        find
            .ancestor(
              of: find.text('Retry'),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            )
            .first,
      );
      await tester.tap(
        find
            .ancestor(
              of: find.text('Retry'),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile refresh failed.'), findsNothing);
    },
  );
  testWidgets(
    'refreshing balances preserves last verified dues but disables collection until verified',
    (tester) async {
      await mount(tester);
      await reveal(tester, financeCard());
      final scope = scopeFor(container.read(adminGymProvider)!, memberId);
      members.historyGate = Completer<MembershipHistory>();
      container.invalidate(memberMembershipsProvider(scope));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Last verified dues'), findsOneWidget);
      expect(
        find.descendant(of: financeCard(), matching: find.text('₹500.00')),
        findsOneWidget,
      );
      expect(find.text('Collect payment'), findsNothing);
      members.historyGate!.complete(
        MembershipHistory.fromResponse(historyJson(populated: true), {
          'page': 1,
          'limit': 20,
          'total': 1,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('To collect'), findsOneWidget);
    },
  );
  testWidgets(
    'scope switch hides the previous member and new identity clears cached content',
    (tester) async {
      await mount(tester);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(find.text('Alex River'), findsNothing);
      expect(find.textContaining('gym context changed'), findsOneWidget);
      container.read(adminGymProvider.notifier).selectGym(gymA);
      await tester.pumpAndSettle();
      members.memberFields['firstName'] = 'Another';
      members.summaryGate = Completer<MemberSummary>();
      container
          .read(appRouterProvider)
          .go('${AppRoutes.members}/$gymB?gymId=$gymA');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Alex River'), findsNothing);
      members.summaryGate!.complete(
        MemberSummary.fromJson(
          summaryJson()..['member'] = {...members.memberFields, 'id': gymB},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Another River'), findsOneWidget);
      expect(
        tester
            .widget<MemberDetailsPage>(find.byType(MemberDetailsPage))
            .memberId,
        gymB,
      );
    },
  );
  testWidgets('profile and section titles are screen-reader headings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    for (final title in [
      'Member details',
      'Alex River',
      'Current membership',
      'Activity',
      'Details',
      'Assigned trainers',
      'Membership history',
    ]) {
      await reveal(tester, find.text(title));
      expect(
        tester
            .getSemantics(find.text(title))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
        reason: title,
      );
    }
    semantics.dispose();
  });

  testWidgets(
    'existing edit, payment and history actions retain 48dp targets',
    (tester) async {
      await mount(tester);
      for (final label in [
        'Edit member',
        'Collect payment',
        'View membership details',
      ]) {
        if (label == 'View membership details') await openHistory(tester);
        await reveal(tester, find.text(label));
        final button = find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is ButtonStyleButton ||
                    widget is FloatingActionButton ||
                    // The round quick actions.
                    widget is InkWell,
              ),
            )
            .first;
        await reveal(tester, button);
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
        expect(button.hitTestable(), findsOneWidget);
      }
      await reveal(tester, find.byTooltip('Back to Members'));
      for (final tooltip in ['Back to Members', 'Refresh member details']) {
        final button = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        );
        expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
      }
    },
  );

  testWidgets(
    'optional section styling leaves other profile sections unchanged',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: ProfileSection(
              title: 'Unchanged section',
              children: [Text('Saved content')],
            ),
          ),
        ),
      );
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Saved content'), findsOneWidget);
      // Neutral sections sit on the page; space separates them.
      expect(find.byType(SoftPanel), findsNothing);
    },
  );

  testWidgets('toned sections and the main block keep their panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Column(
            children: [
              ProfileSection(
                title: 'Plan',
                tone: AppTone.plan,
                children: [Text('Plan content')],
              ),
              ProfileSection(
                title: 'Balance',
                card: true,
                icon: Icons.account_balance_wallet_outlined,
                children: [Text('Balance content')],
              ),
              ProfileSection(
                title: 'Plain',
                icon: Icons.info_outline,
                children: [Text('Plain content')],
              ),
            ],
          ),
        ),
      ),
    );
    final panels = tester.widgetList<SoftPanel>(find.byType(SoftPanel));
    expect(panels.map((panel) => panel.tone), [AppTone.plan, AppTone.neutral]);
    // Only the boxed section shows its heading icon.
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('neutral profile surface keeps text contrast in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.fromValues()),
          ],
          child: MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            home: Scaffold(
              body: MemberProfileCard(
                member: MemberProfile.fromJson(profileJson()),
                scope: (userId: 'user', gymId: gymA, memberId: memberId),
              ),
            ),
          ),
        ),
      );
      final panel = tester.widget<SoftPanel>(find.byType(SoftPanel));
      final backgrounds = [
        AppSurfaces.of(
          tester.element(find.byType(SoftPanel)),
        ).panel(panel.tone, brightness),
      ];
      final context = tester.element(find.text('Alex River'));
      for (final label in ['Alex River', 'Member code: ME01']) {
        final text = tester.widget<Text>(find.text(label));
        final color =
            text.style?.color ?? Theme.of(context).colorScheme.onSurface;
        for (final background in backgrounds) {
          final a = color.computeLuminance(), b = background.computeLuminance();
          expect(
            ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
            greaterThanOrEqualTo(4.5),
            reason: label,
          );
        }
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'profile and money remain readable at triple text with reduced motion, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final summary = await members.summary(gymA, memberId);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appConfigProvider.overrideWithValue(AppConfig.fromValues()),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(3),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MemberProfileCard(
                          member: summary.member,
                          scope: (
                            userId: 'user',
                            gymId: gymA,
                            memberId: memberId,
                          ),
                        ),
                        SavedMembershipSummary(
                          membership: summary.currentSubscription!,
                        ),
                        const MemberAmounts(
                          paidPaise: 100000,
                          balancePaise: 50000,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await Scrollable.ensureVisible(
          tester.element(find.text('₹500.00')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        expect(find.text('₹500.00').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(375, 812),
    const Size(430, 932),
    const Size(812, 375),
    const Size(768, 1024),
    const Size(1024, 768),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('details adapts to $size with bounded content, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await mount(tester);
        expect(
          tester.getSize(find.byType(MemberProfileCard)).width,
          lessThanOrEqualTo(AppSpacing.contentWidth),
        );
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('Collect payment'));
        expect(find.text('Collect payment').hitTestable(), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text('Collect payment')).dy,
          lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
        );
        await reveal(tester, find.text('View membership details'));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      '320px details with double text remains scrollable above navigation, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 860);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        members.memberFields.addAll({
          'firstName': 'Alexandria',
          'lastName': 'Long Member Name',
          'address': {
            'line1': 'A long saved address',
            'city': 'Pune',
            'countryCode': 'IN',
          },
        });
        await mount(tester);
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('Collect payment'));
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomLeft(find.text('Collect payment')).dy,
          lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
        );
        await reveal(tester, find.text('View membership details'));
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomLeft(find.text('View membership details')).dy,
          lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
        );
      },
    );
  }
  testWidgets(
    'payment action belongs to the financial summary and never overlays membership content',
    (tester) async {
      await mount(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
      await reveal(tester, find.text('Collect payment'));
      final pay = find.ancestor(
        of: find.text('Collect payment'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(find.descendant(of: financeCard(), matching: pay), findsOneWidget);
      expect(pay.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(pay).dy,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      expect(find.text('Collect payment'), findsOneWidget);
      expect(payments.collections, isEmpty);
      final memberScaffolds = find.descendant(
        of: find.byType(MemberDetailsPage),
        matching: find.byType(Scaffold),
      );
      for (final widget in tester.widgetList<Scaffold>(memberScaffolds)) {
        expect(widget.floatingActionButton, isNull);
      }
    },
  );

  testWidgets(
    'dues card opens Member Details with its guarded inline collection action',
    (tester) async {
      await mount(tester);
      container
          .read(appRouterProvider)
          .go('${AppRoutes.outstandingDues}?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Collect payment'), findsNothing);
      await reveal(tester, find.text('Alex River'));
      await tester.tap(find.text('Alex River'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberDetailsPage), findsOneWidget);
      await reveal(tester, find.text('Collect payment'));
      expect(
        find.ancestor(
          of: find.text('Collect payment'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('durable-operation verification hides collection until ready', (
    tester,
  ) async {
    final storage = TestOnboardingStorage();
    await mount(tester, recoveryStorage: storage);
    await reveal(tester, financeCard());
    final scope = (
      member: scopeFor(container.read(adminGymProvider)!, memberId),
      subscriptionId: subscriptionId,
    );
    storage.readGate = Completer<void>();
    container.invalidate(paymentCollectionProvider(scope));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Collect payment'), findsNothing);
    expect(payments.collections, isEmpty);
    storage.readGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Collect payment'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'unresolved saved collection hides Pay Now and opens the existing recovery sheet',
    (tester) async {
      await mount(tester);
      final scope = (
        member: scopeFor(container.read(adminGymProvider)!, memberId),
        subscriptionId: subscriptionId,
      );
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      payments.failure = const BillingFailure(
        'Synthetic uncertain result',
        uncertain: true,
      );
      await controller.collect(
        ManualPayment(
          amountPaise: 10000,
          method: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 3, 2),
        ),
        50000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Collect payment'), findsNothing);
      expect(find.text('Collect payment'), findsNothing);
      await reveal(tester, find.text('Review saved payment · Monthly'));
      await tester.tap(find.text('Review saved payment · Monthly'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentSheet), findsOneWidget);
      expect(find.text('Saved payment awaiting confirmation'), findsOneWidget);
      expect(find.text('Retry saved payment'), findsOneWidget);
      expect(payments.collections, hasLength(1));
    },
  );

  testWidgets(
    'failed saved-operation verification never exposes a fresh payment action',
    (tester) async {
      final storage = TestOnboardingStorage();
      await mount(tester, recoveryStorage: storage);
      final scope = (
        member: scopeFor(container.read(adminGymProvider)!, memberId),
        subscriptionId: subscriptionId,
      );
      storage.failRead = true;
      container.invalidate(paymentCollectionProvider(scope));
      await tester.pumpAndSettle();
      expect(find.text('Collect payment'), findsNothing);
      expect(payments.collections, isEmpty);
      await reveal(tester, find.text('Review saved payment · Monthly'));
      expect(find.text('Review saved payment · Monthly'), findsOneWidget);
    },
  );
  testWidgets(
    'cancelled membership still exposes saved-operation recovery without Pay Now',
    (tester) async {
      await mount(tester);
      final memberScope = scopeFor(container.read(adminGymProvider)!, memberId);
      final scope = (member: memberScope, subscriptionId: subscriptionId);
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      payments.failure = const BillingFailure(
        'Synthetic uncertain result',
        uncertain: true,
      );
      await controller.collect(
        ManualPayment(
          amountPaise: 10000,
          method: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 3, 2),
        ),
        50000,
      );
      members.debts[memberId]!.single.addAll({
        'status': 'cancelled',
        'isCurrentlyActive': false,
      });
      container.invalidate(memberMembershipsProvider(memberScope));
      container.invalidate(memberSummaryProvider(memberScope));
      await tester.pumpAndSettle();
      expect(find.text('Collect payment'), findsNothing);
      await reveal(tester, find.text('Review saved payment · Monthly'));
      await tester.tap(find.text('Review saved payment · Monthly'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentSheet), findsOneWidget);
      expect(find.text('Saved payment awaiting confirmation'), findsOneWidget);
      expect(payments.collections, hasLength(1));
    },
  );

  // Directory dues are computed by the server's member overview now; see the
  // backend overview tests and member_widgets_test 'dues row offers Collect'.
}
