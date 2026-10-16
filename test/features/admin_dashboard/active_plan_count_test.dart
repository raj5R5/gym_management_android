import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/providers/plan_providers.dart';
import '../auth/auth_fakes.dart';
import '../memberships/billing_fakes.dart';
import 'dashboard_fakes.dart';

class PendingPlans extends FakeMembershipRepository {
  final requests =
      <({String gymId, Completer<BillingPage<MembershipPlan>> result})>[];
  @override
  Future<BillingPage<MembershipPlan>> plans(String gymId, int page) {
    final result = Completer<BillingPage<MembershipPlan>>();
    requests.add((gymId: gymId, result: result));
    return result.future;
  }
}

void main() {
  late ProviderContainer container;
  late FakeMembershipRepository plans;
  ProviderContainer create(FakeMembershipRepository repository) =>
      ProviderContainer(
        overrides: [
          authApiServiceProvider.overrideWithValue(
            FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
          ),
          credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
          membershipRepositoryProvider.overrideWithValue(repository),
        ],
      );
  setUp(() {
    plans = FakeMembershipRepository();
    container = create(plans);
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());

  test('no active admin scope makes no plan request', () async {
    expect(await container.read(activePlanCountProvider.future), isNull);
    expect(plans.operations, isEmpty);
  });
  test(
    'uses authoritative pagination total once, independent of revenue period',
    () async {
      await login();
      plans.total = 37;
      container.listen(activePlanCountProvider, (_, _) {});
      expect(await container.read(activePlanCountProvider.future), 37);
      container
          .read(dashboardQueryProvider.notifier)
          .selectRange(CalendarDate(2026, 3, 1), CalendarDate(2026, 3, 7));
      expect(await container.read(activePlanCountProvider.future), 37);
      expect(plans.operations, ['plans:$gymA:1']);
    },
  );
  test(
    'plan save and status edits invalidate count and logout clears it',
    () async {
      await login();
      container.listen(activePlanCountProvider, (_, _) {});
      expect(await container.read(activePlanCountProvider.future), 1);
      final gym = container.read(adminGymProvider)!;
      plans.total = 0;
      final result = await container
          .read(planMutationProvider((gym: gym, planId: planId)).notifier)
          .save(
            PlanDraft(
              name: 'Monthly',
              durationDays: 30,
              pricePaise: 150000,
              status: 'inactive',
            ),
          );
      expect(result, isNotNull);
      expect(await container.read(activePlanCountProvider.future), 0);
      await container.read(sessionControllerProvider.notifier).logout();
      expect(await container.read(activePlanCountProvider.future), isNull);
      expect(
        plans.operations.where((operation) => operation.startsWith('plans:')),
        hasLength(2),
      );
    },
  );
  test('late old-gym result cannot replace current-gym count', () async {
    container.dispose();
    final pending = PendingPlans();
    container = create(pending);
    await login();
    container.listen(activePlanCountProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    final latest = container.read(activePlanCountProvider.future);
    await Future<void>.delayed(Duration.zero);
    pending.requests[1].result.complete(BillingPage([], pagination(1, 0)));
    expect(await latest, 0);
    pending.requests[0].result.complete(
      BillingPage([MembershipPlan.fromJson(planJson())], pagination(1, 37)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(activePlanCountProvider).requireValue, 0);
    expect(pending.requests.map((request) => request.gymId), [gymA, gymB]);
  });
}
