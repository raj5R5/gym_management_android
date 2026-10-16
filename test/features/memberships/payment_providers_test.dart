import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart'
    show OnboardingOperationQueue;
import '../members/onboarding_fakes.dart'
    show TestOnboardingStorage, onboardingUrl;
import 'package:gym_management_app/core/config/app_config.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/memberships/data/billing_failure.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../members/member_fakes.dart';
import 'billing_fakes.dart';
import 'payment_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakePaymentRepository payments;
  late DueMembersFake members;
  late FakeDashboardRepository dashboard;
  late FakeMembershipRepository memberships;
  var keys = 0;
  final scope = (
    member: (
      userId: syntheticIdentity().user.id,
      gymId: gymA,
      memberId: memberId,
    ),
    subscriptionId: subscriptionId,
  );
  ManualPayment cash([int amount = 10000]) => ManualPayment(
    amountPaise: amount,
    method: PaymentMethod.cash,
    paidAt: DateTime.utc(2026, 1, 1),
  );
  setUp(() async {
    keys = 0;
    payments = FakePaymentRepository();
    members = DueMembersFake();
    dashboard = FakeDashboardRepository();
    memberships = FakeMembershipRepository();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: onboardingUrl),
        ),
        pendingPaymentStoreProvider.overrideWithValue(
          PendingPaymentStore(
            storage: TestOnboardingStorage(),
            queue: OnboardingOperationQueue(),
          ),
        ),
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        paymentRepositoryProvider.overrideWithValue(payments),
        memberRepositoryProvider.overrideWithValue(members),
        membershipRepositoryProvider.overrideWithValue(memberships),
        dashboardRepositoryProvider.overrideWithValue(dashboard),
        paymentKeyFactoryProvider.overrideWithValue(() => 'test-key-${++keys}'),
      ],
    );
    await container
        .read(sessionControllerProvider.notifier)
        .login(
          email: 'person@example.invalid',
          password: syntheticCredential(),
        );
  });
  tearDown(() => container.dispose());
  test(
    'payment timezone shares existing server metadata without duplicate requests',
    () async {
      final gym = container.read(adminGymProvider)!;
      container.listen(dashboardProvider, (_, _) {});
      container.listen(paymentTimezoneProvider(gym), (_, _) {});
      await container.read(dashboardProvider.future);
      expect(
        await container.read(paymentTimezoneProvider(gym).future),
        'Asia/Kolkata',
      );
      expect(
        await container.read(paymentTimezoneProvider(gym).future),
        'Asia/Kolkata',
      );
      expect(dashboard.requests, hasLength(1));
    },
  );
  test(
    'payment timezone never returns metadata for a different gym scope',
    () async {
      final gym = container.read(adminGymProvider)!;
      container.listen(paymentTimezoneProvider(gym), (_, _) {});
      await container.read(paymentTimezoneProvider(gym).future);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await container.pump();
      expect(await container.read(paymentTimezoneProvider(gym).future), isNull);
      final next = container.read(adminGymProvider)!;
      expect(
        await container.read(paymentTimezoneProvider(next).future),
        'Asia/Kolkata',
      );
      expect(dashboard.requests.last.gymId, gymB);
    },
  );
  test(
    'membership changes invalidate each listened financial request once',
    () async {
      final gym = container.read(adminGymProvider)!;
      final revenue = (gym: gym, from: '2026-03-01', to: '2026-03-02', page: 1);
      container.listen(revenueDetailsProvider(revenue), (_, _) {});
      container.listen(outstandingDuesProvider, (_, _) {});
      await container.read(revenueDetailsProvider(revenue).future);
      await container.read(outstandingDuesProvider.future);
      final listCount = members.listCalls.length;
      expect(
        await container
            .read(billingMutationProvider(scope.member).notifier)
            .cancel(subscriptionId, 'Member request'),
        isNotNull,
      );
      await container.pump();
      await container.read(revenueDetailsProvider(revenue).future);
      await container.read(outstandingDuesProvider.future);
      expect(payments.ranges, hasLength(2));
      expect(members.listCalls, hasLength(listCount + 1));
      expect(payments.collections, isEmpty);
    },
  );

  test(
    'positive validation prevents overpayment from reaching transport',
    () async {
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      expect(await controller.collect(cash(50001), 50000), isNull);
      expect(payments.collections, isEmpty);
      expect(keys, 0);
    },
  );
  test('two in-flight taps produce one payment and one key', () async {
    payments.gate = Completer<RecordedPayment>();
    final controller = container.read(
      paymentCollectionProvider(scope).notifier,
    );
    final pending = controller.collect(cash(), 50000);
    expect(await controller.collect(cash(), 50000), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(payments.collections, hasLength(1));
    expect(keys, 1);
    payments.gate!.complete(payments.confirmation(payments.collections.single));
    expect((await pending)!.amountPaise, 10000);
    expect(await controller.collect(cash(), 50000), isNull);
    expect(payments.collections, hasLength(1));
  });
  test(
    'timeout retry uses identical command/body/key/time and no second key',
    () async {
      payments.failure = const BillingFailure(
        'Connection interrupted',
        uncertain: true,
      );
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      await controller.collect(cash(), 50000);
      final saved = payments.collections.single;
      expect(controller.canRetry, isTrue);
      expect(await controller.collect(cash(20000), 50000), isNull);
      payments.failure = null;
      expect(await controller.retrySaved(), isNotNull);
      expect(payments.collections.last.frozenJson, saved.frozenJson);
      expect(payments.collections.last.key, saved.key);
      expect(keys, 1);
    },
  );
  test(
    'timeout followed by rejection retains uncertainty and original command',
    () async {
      payments.failure = const BillingFailure('Timeout', uncertain: true);
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      await controller.collect(cash(), 50000);
      payments.failure = const BillingFailure('Overpayment');
      await controller.retrySaved();
      expect(
        (container.read(paymentCollectionProvider(scope)).error!
                as BillingFailure)
            .uncertain,
        isTrue,
      );
      expect(controller.canRetry, isTrue);
      expect(keys, 1);
      expect(
        payments.collections.first.frozenJson,
        payments.collections.last.frozenJson,
      );
      expect(payments.collections.first.key, payments.collections.last.key);
    },
  );
  test('idempotency conflict blocks retry and replacement', () async {
    payments.failure = const BillingFailure(
      'Conflict',
      uncertain: true,
      code: 'IDEMPOTENCY_KEY_CONFLICT',
    );
    final controller = container.read(
      paymentCollectionProvider(scope).notifier,
    );
    await controller.collect(cash(), 50000);
    expect(controller.canRetry, isFalse);
    expect(await controller.retrySaved(), isNull);
    expect(await controller.collect(cash(20000), 50000), isNull);
    expect(payments.collections, hasLength(1));
    expect(keys, 1);
  });
  test(
    'first definite rejection permits a validated correction under a fresh key',
    () async {
      payments.failure = const BillingFailure(
        'Reference rejected',
        code: 'DUPLICATE_PAYMENT_REFERENCE',
        httpStatus: 409,
      );
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      await controller.collect(cash(), 50000);
      payments.failure = null;
      expect(await controller.collect(cash(20000), 50000), isNotNull);
      expect(keys, 2);
      expect(
        payments.collections.first.key,
        isNot(payments.collections.last.key),
      );
    },
  );
  test(
    'scope change in flight prevents success and cache application to another gym',
    () async {
      payments.gate = Completer<RecordedPayment>();
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      final pending = controller.collect(cash(), 50000);
      await Future<void>.delayed(Duration.zero);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await container.pump();
      payments.gate!.complete(
        payments.confirmation(payments.collections.single),
      );
      expect(await pending, isNull);
      expect(await controller.retrySaved(), isNull);
      expect(dashboard.requests, isEmpty);
    },
  );
  test(
    'confirmed collection invalidates dashboard, dues, details and payment lists',
    () async {
      payments.onCollection = members.collect;
      container.listen(dashboardProvider, (_, _) {});
      container.listen(outstandingDuesProvider, (_, _) {});
      final detail = (scope: scope.member, subscriptionId: subscriptionId);
      final history = (scope: scope.member, page: 1);
      container.listen(membershipDetailProvider(detail), (_, _) {});
      container.listen(paymentHistoryProvider(history), (_, _) {});
      final revenue = (
        gym: (userId: scope.member.userId, gymId: gymA),
        from: '2026-03-01',
        to: '2026-03-01',
        page: 1,
      );
      container.listen(revenueDetailsProvider(revenue), (_, _) {});
      await container.read(dashboardProvider.future);
      await container.read(outstandingDuesProvider.future);
      await container.read(membershipDetailProvider(detail).future);
      await container.read(paymentHistoryProvider(history).future);
      await container.read(revenueDetailsProvider(revenue).future);
      expect(
        (await container.read(outstandingDuesProvider.future))!.totalPaise,
        50000,
      );
      final controller = container.read(
        paymentCollectionProvider(scope).notifier,
      );
      expect(await controller.collect(cash(), 50000), isNotNull);
      await container.pump();
      await container.read(dashboardProvider.future);
      await container.read(paymentHistoryProvider(history).future);
      await container.read(revenueDetailsProvider(revenue).future);
      expect(
        (await container.read(outstandingDuesProvider.future))!.totalPaise,
        40000,
      );
      expect(
        (await container.read(
          membershipDetailProvider(detail).future,
        ))!.payments.balancePaise,
        40000,
      );
      expect(dashboard.requests, hasLength(2));
      expect(payments.ranges, hasLength(2));
      expect(
        memberships.operations.where((value) => value.startsWith('payments:')),
        hasLength(2),
      );
    },
  );
}
