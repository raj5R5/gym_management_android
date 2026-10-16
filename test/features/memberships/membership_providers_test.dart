import 'dart:async';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'billing_fakes.dart';
import 'package:gym_management_app/features/memberships/providers/plan_providers.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';

void main() {
  late ProviderContainer container;
  late FakeMembershipRepository billing;
  late FakeMemberRepository members;
  late FakeDashboardRepository dashboard;
  setUp(() {
    billing = FakeMembershipRepository();
    members = FakeMemberRepository()
      ..populated = true
      ..historyRecords = expiredHistoryFixture();
    dashboard = FakeDashboardRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        memberRepositoryProvider.overrideWithValue(members),
        membershipRepositoryProvider.overrideWithValue(billing),
        dashboardRepositoryProvider.overrideWithValue(dashboard),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());
  MemberScope scope() => scopeFor(container.read(adminGymProvider)!, memberId);
  for (final operation in ['purchase', 'cancel', 'renew']) {
    test(
      '$operation refreshes outstanding dues with the selected date filter',
      () async {
        await login();
        container.listen(dashboardProvider, (_, _) {});
        container
            .read(dashboardQueryProvider.notifier)
            .selectRange(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 7));
        await container.read(dashboardProvider.future);
        final before = dashboard.requests.length;
        dashboard.result = GymDashboard.fromJson(
          dashboardJson(outstanding: 25000),
        );
        final controller = container.read(
          billingMutationProvider(scope()).notifier,
        );
        final result = await switch (operation) {
          'purchase' => controller.purchase(PurchaseDraft(planId: planId)),
          'cancel' => controller.cancel(subscriptionId, 'Requested'),
          _ => controller.renew(subscriptionId),
        };
        expect(result, isNotNull);
        expect(
          (await container.read(
            dashboardProvider.future,
          ))!.payments.outstandingAmountPaise,
          25000,
        );
        expect(dashboard.requests.length, before + 1);
        expect(dashboard.requests.last.gymId, gymA);
        expect(dashboard.requests.last.query.toParameters(), {
          'from': '2026-03-01',
          'to': '2026-03-07',
        });
      },
    );
  }
  test(
    'unauthenticated and foreign scope reads do not reach repository',
    () async {
      final request = (
        scope: (userId: 'none', gymId: gymA, memberId: memberId),
        page: 1,
      );
      expect(await container.read(activePlansProvider(request).future), isNull);
      expect(
        await container.read(paymentHistoryProvider(request).future),
        isNull,
      );
      expect(
        await container
            .read(billingMutationProvider(request.scope).notifier)
            .purchase(PurchaseDraft(planId: planId)),
        isNull,
      );
      expect(billing.operations, isEmpty);
    },
  );

  for (final operation in ['purchase', 'renew']) {
    test(
      '$operation rechecks paginated server lifecycle and blocks paid/unpaid active memberships',
      () async {
        await login();
        members.historyRecords = [
          for (var index = 0; index < 20; index++)
            subscriptionJson()..addAll({
              'id': (100 + index).toRadixString(16).padLeft(24, '0'),
              'status': 'expired',
              'isCurrentlyActive': false,
            }),
          subscriptionJson()..addAll({'isCurrentlyActive': false}),
        ];
        final controller = container.read(
          billingMutationProvider(scope()).notifier,
        );
        final result = operation == 'purchase'
            ? await controller.purchase(PurchaseDraft(planId: planId))
            : await controller.renew(subscriptionId);
        expect(result, isNull);
        expect(billing.purchases, isEmpty);
        expect(billing.renewals, isEmpty);
        expect(members.operations, contains('history:2'));
        final error =
            container.read(billingMutationProvider(scope())).error
                as BillingFailure;
        expect(error.message, contains('unexpired membership'));
        expect(error.uncertain, false);
      },
    );
    test(
      '$operation allowed for expired unpaid history and cancelled records',
      () async {
        await login();
        members.historyRecords = [
          ...expiredHistoryFixture(),
          subscriptionJson(cancelled: true),
        ];
        final controller = container.read(
          billingMutationProvider(scope()).notifier,
        );
        final result = operation == 'purchase'
            ? await controller.purchase(PurchaseDraft(planId: planId))
            : await controller.renew(subscriptionId);
        expect(result, isNotNull);
      },
    );
  }
  test(
    'scope change during fresh eligibility read makes no membership write',
    () async {
      await login();
      members.historyGate = Completer<MembershipHistory>();
      final controller = container.read(
        billingMutationProvider(scope()).notifier,
      );
      final pending = controller.purchase(PurchaseDraft(planId: planId));
      await Future<void>.delayed(Duration.zero);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      members.historyGate!.complete(
        MembershipHistory.fromResponse(historyJson(), {
          'page': 1,
          'limit': 20,
          'total': 0,
        }),
      );
      expect(await pending, isNull);
      expect(billing.purchases, isEmpty);
    },
  );
  test('plans loading then typed success', () async {
    await login();
    billing.planGate = Completer<BillingPage<MembershipPlan>>();
    final request = (scope: scope(), page: 1);
    final pending = container.read(activePlansProvider(request).future);
    expect(container.read(activePlansProvider(request)).isLoading, isTrue);
    billing.planGate!.complete(
      BillingPage([MembershipPlan.fromJson(planJson())], pagination(1, 1)),
    );
    expect((await pending)!.items.single.id, planId);
  });
  test('empty, error, manual retry and refresh states', () async {
    await login();
    final request = (scope: scope(), page: 1);
    billing.failure = const BillingFailure('Offline');
    container.listen(paymentHistoryProvider(request), (_, _) {});
    await expectLater(
      container.read(paymentHistoryProvider(request).future),
      throwsA(isA<BillingFailure>()),
    );
    billing.failure = null;
    billing.empty = true;
    container.invalidate(paymentHistoryProvider(request));
    expect(
      (await container.read(paymentHistoryProvider(request).future))!.items,
      isEmpty,
    );
    billing.empty = false;
    container.invalidate(paymentHistoryProvider(request));
    expect(
      (await container.read(
        paymentHistoryProvider(request).future,
      ))!.items.length,
      1,
    );
    expect(billing.operations.length, 3);
  });
  test('read response cannot remain visible after gym switch', () async {
    await login();
    final request = (scope: scope(), page: 1);
    billing.planGate = Completer<BillingPage<MembershipPlan>>();
    container.listen(activePlansProvider(request), (_, _) {});
    container.read(activePlansProvider(request).future);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    expect(await container.read(activePlansProvider(request).future), isNull);
    billing.planGate!.complete(
      BillingPage([MembershipPlan.fromJson(planJson())], pagination(1, 1)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(activePlansProvider(request)).asData!.value, isNull);
  });
  test(
    'purchase prevents duplicates and refreshes existing read caches',
    () async {
      await login();
      final current = scope();
      container.listen(memberSummaryProvider(current), (_, _) {});
      await container.read(memberSummaryProvider(current).future);
      billing.writeGate = Completer<BillingResult>();
      final controller = container.read(
        billingMutationProvider(current).notifier,
      );
      final pending = controller.purchase(PurchaseDraft(planId: planId));
      expect(
        container.read(billingMutationProvider(current)).isLoading,
        isTrue,
      );
      expect(await controller.purchase(PurchaseDraft(planId: planId)), isNull);
      billing.writeGate!.complete(billingResult());
      expect(await pending, isNotNull);
      await container.read(memberSummaryProvider(current).future);
      expect(
        members.operations.where((op) => op.startsWith('summary')).length,
        2,
      );
      expect(billing.purchases.length, 1);
    },
  );
  test(
    'known purchase rejection is safe and permits a new explicit attempt',
    () async {
      await login();
      final current = scope();
      final controller = container.read(
        billingMutationProvider(current).notifier,
      );
      billing.failure = const BillingFailure('Overlap');
      expect(await controller.purchase(PurchaseDraft(planId: planId)), isNull);
      expect(
        container.read(billingMutationProvider(current)).error,
        isA<BillingFailure>(),
      );
      billing.failure = null;
      expect(
        await controller.purchase(PurchaseDraft(planId: planId)),
        isNotNull,
      );
    },
  );
  test(
    'uncertain purchase blocks all writes until both histories recheck',
    () async {
      await login();
      final current = scope();
      final controller = container.read(
        billingMutationProvider(current).notifier,
      );
      billing.failure = const BillingFailure('Verify history', uncertain: true);
      await controller.purchase(PurchaseDraft(planId: planId));
      billing.failure = null;
      expect(await controller.purchase(PurchaseDraft(planId: planId)), isNull);
      expect(await controller.cancel(subscriptionId, ''), isNull);
      expect(await controller.renew(subscriptionId), isNull);
      expect(billing.purchases.length, 1);
      expect(await controller.recheck(), isTrue);
      expect(members.operations, contains('history:1'));
      expect(billing.operations, contains('payments:$gymA:$memberId:1'));
      expect(
        await controller.purchase(PurchaseDraft(planId: planId)),
        isNotNull,
      );
      expect(billing.purchases.length, 2);
    },
  );
  test('failed recheck leaves write lock in place', () async {
    await login();
    final controller = container.read(
      billingMutationProvider(scope()).notifier,
    );
    billing.failure = const BillingFailure('Unknown outcome', uncertain: true);
    await controller.purchase(PurchaseDraft(planId: planId));
    expect(await controller.recheck(), isFalse);
    billing.failure = null;
    expect(await controller.purchase(PurchaseDraft(planId: planId)), isNull);
    expect(billing.purchases.length, 1);
  });
  test('uncertain write lock survives leaving and returning to gym', () async {
    await login();
    final current = scope();
    container.listen(billingMutationProvider(current), (_, _) {});
    final controller = container.read(
      billingMutationProvider(current).notifier,
    );
    billing.failure = const BillingFailure('Check history', uncertain: true);
    await controller.purchase(PurchaseDraft(planId: planId));
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await Future<void>.delayed(Duration.zero);
    container.read(adminGymProvider.notifier).selectGym(gymA);
    await Future<void>.delayed(Duration.zero);
    billing.failure = null;
    expect(container.read(billingMutationProvider(current)).hasError, isTrue);
    expect(await controller.purchase(PurchaseDraft(planId: planId)), isNull);
    expect(billing.purchases.length, 1);
  });
  test('cancel and renew publish only server result', () async {
    await login();
    final controller = container.read(
      billingMutationProvider(scope()).notifier,
    );
    expect(
      (await controller.cancel(
        subscriptionId,
        'Requested',
      ))!.subscription.status,
      'cancelled',
    );
    expect(
      (await controller.renew(subscriptionId))!.subscription.previousId,
      subscriptionId,
    );
    expect(billing.operations, ['cancel:Requested', 'renew']);
  });
  for (final change in ['gym', 'logout', 'same-account-relogin']) {
    test('pending purchase ignored after $change', () async {
      await login();
      final current = scope();
      container.listen(billingMutationProvider(current), (_, _) {});
      billing.writeGate = Completer<BillingResult>();
      final pending = container
          .read(billingMutationProvider(current).notifier)
          .purchase(PurchaseDraft(planId: planId));
      if (change == 'gym') {
        container.read(adminGymProvider.notifier).selectGym(gymB);
      } else {
        await container.read(sessionControllerProvider.notifier).logout();
        if (change == 'same-account-relogin') await login();
      }
      await Future<void>.delayed(Duration.zero);
      billing.writeGate!.complete(billingResult());
      expect(await pending, isNull);
      expect(
        container.read(billingMutationProvider(current)).asData?.value,
        isNull,
      );
    });
  }
  test('managed plan list loading, empty, failure and refresh', () async {
    await login();
    final gym = container.read(adminGymProvider)!;
    final request = (gym: gym, page: 1);
    billing.planGate = Completer<BillingPage<MembershipPlan>>();
    container.listen(managedPlansProvider(request), (_, _) {});
    final pending = container.read(managedPlansProvider(request).future);
    expect(container.read(managedPlansProvider(request)).isLoading, isTrue);
    billing.planGate!.complete(BillingPage([], pagination(1, 0)));
    expect((await pending)!.items, isEmpty);
    billing.planGate = null;
    billing.failure = const BillingFailure('Offline');
    container.invalidate(managedPlansProvider(request));
    await expectLater(
      container.read(managedPlansProvider(request).future),
      throwsA(isA<BillingFailure>()),
    );
    billing.failure = null;
    container.invalidate(managedPlansProvider(request));
    expect(
      (await container.read(
        managedPlansProvider(request).future,
      ))!.items.length,
      1,
    );
  });
  test(
    'plan save invalidates active selection and blocks duplicate saves',
    () async {
      await login();
      final gym = container.read(adminGymProvider)!;
      final request = (scope: scope(), page: 1);
      container.listen(activePlansProvider(request), (_, _) {});
      await container.read(activePlansProvider(request).future);
      billing.planSaveGate = Completer<MembershipPlan>();
      final controller = container.read(
        planMutationProvider((gym: gym, planId: '')).notifier,
      );
      final draft = PlanDraft(
        name: 'New',
        durationDays: 30,
        pricePaise: 0,
        status: 'active',
      );
      final pending = controller.save(draft);
      expect(await controller.save(draft), isNull);
      billing.planSaveGate!.complete(
        MembershipPlan.fromJson({
          ...planJson(),
          ...draft.toJson(editing: false),
        }),
      );
      expect((await pending)!.name, 'New');
      expect(
        (await container.read(
          activePlansProvider(request).future,
        ))!.items.single.name,
        'New',
      );
      expect(billing.planWrites.length, 1);
    },
  );
  test('plan uncertainty blocks write until explicit recheck', () async {
    await login();
    final gym = container.read(adminGymProvider)!;
    final controller = container.read(
      planMutationProvider((gym: gym, planId: '')).notifier,
    );
    final draft = PlanDraft(
      name: 'New',
      durationDays: 30,
      pricePaise: 0,
      status: 'active',
    );
    billing.failure = const BillingFailure('Recheck plans', uncertain: true);
    await controller.save(draft);
    billing.failure = null;
    expect(await controller.save(draft), isNull);
    await controller.recheck();
    expect(await controller.save(draft), isNotNull);
    expect(billing.planWrites.length, 2);
  });
  test('foreign plan scope cannot read or save', () async {
    await login();
    final gym = container.read(adminGymProvider)!;
    container.read(adminGymProvider.notifier).selectGym(gymB);
    expect(
      await container.read(managedPlansProvider((gym: gym, page: 1)).future),
      isNull,
    );
    expect(
      await container
          .read(planMutationProvider((gym: gym, planId: '')).notifier)
          .save(
            PlanDraft(
              name: 'A',
              durationDays: 1,
              pricePaise: 0,
              status: 'active',
            ),
          ),
      isNull,
    );
    expect(billing.planWrites, isEmpty);
  });
  test(
    'pending plan result ignored after logout and same-account login',
    () async {
      await login();
      final gym = container.read(adminGymProvider)!;
      final provider = planMutationProvider((gym: gym, planId: ''));
      container.listen(provider, (_, _) {});
      billing.planSaveGate = Completer<MembershipPlan>();
      final pending = container
          .read(provider.notifier)
          .save(
            PlanDraft(
              name: 'A',
              durationDays: 1,
              pricePaise: 0,
              status: 'active',
            ),
          );
      await container.read(sessionControllerProvider.notifier).logout();
      await login();
      billing.planSaveGate!.complete(MembershipPlan.fromJson(planJson()));
      expect(await pending, isNull);
    },
  );
  test(
    'confirmed cancellation refreshes members, details, histories, dues and dashboard without resetting filters',
    () async {
      await login();
      final current = scope();
      final history = (scope: current, page: 1);
      final detail = (scope: current, subscriptionId: subscriptionId);
      container.read(memberQueryProvider.notifier).apply(search: 'Alex');
      container.listen(membersProvider, (_, _) {});
      container.listen(memberSummaryProvider(current), (_, _) {});
      container.listen(memberHistoryProvider(history), (_, _) {});
      container.listen(membershipDetailProvider(detail), (_, _) {});
      container.listen(paymentHistoryProvider(history), (_, _) {});
      container.listen(outstandingDuesProvider, (_, _) {});
      container.listen(dashboardProvider, (_, _) {});
      await Future.wait([
        container.read(membersProvider.future),
        container.read(memberSummaryProvider(current).future),
        container.read(memberHistoryProvider(history).future),
        container.read(membershipDetailProvider(detail).future),
        container.read(paymentHistoryProvider(history).future),
        container.read(outstandingDuesProvider.future),
        container.read(dashboardProvider.future),
      ]);
      final lists = members.listCalls.length;
      final details = members.operations
          .where((e) => e.startsWith('membership:'))
          .length;
      final histories = members.operations
          .where((e) => e.startsWith('history:'))
          .length;
      final summaries = members.operations
          .where((e) => e.startsWith('summary:'))
          .length;
      final payments = billing.operations
          .where((e) => e.startsWith('payments:'))
          .length;
      final dashboards = dashboard.requests.length;
      final result = await container
          .read(billingMutationProvider(current).notifier)
          .cancel(subscriptionId, 'Requested');
      expect(result!.subscription.status, 'cancelled');
      await Future.wait([
        container.read(membersProvider.future),
        container.read(memberSummaryProvider(current).future),
        container.read(memberHistoryProvider(history).future),
        container.read(membershipDetailProvider(detail).future),
        container.read(paymentHistoryProvider(history).future),
        container.read(outstandingDuesProvider.future),
        container.read(dashboardProvider.future),
      ]);
      expect(members.listCalls.length, greaterThan(lists));
      expect(
        members.operations.where((e) => e.startsWith('membership:')).length,
        greaterThan(details),
      );
      expect(
        members.operations.where((e) => e.startsWith('history:')).length,
        greaterThan(histories),
      );
      expect(
        members.operations.where((e) => e.startsWith('summary:')).length,
        greaterThan(summaries),
      );
      expect(
        billing.operations.where((e) => e.startsWith('payments:')).length,
        greaterThan(payments),
      );
      expect(dashboard.requests.length, greaterThan(dashboards));
      expect(container.read(memberQueryProvider).search, 'Alex');
      expect(
        billing.operations.where((e) => e.startsWith('cancel:')).toList(),
        ['cancel:Requested'],
      );
    },
  );
}
