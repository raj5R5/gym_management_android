import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/onboarding_failure.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'onboarding_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeOnboardingRepository repository;
  late TestOnboardingStorage platform;
  late AppConfig config;
  setUp(() {
    config = AppConfig.fromValues(apiBaseUrl: onboardingUrl);
    repository = FakeOnboardingRepository();
    platform = TestOnboardingStorage();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        memberOnboardingRepositoryProvider.overrideWithValue(repository),
        pendingOnboardingStoreProvider.overrideWithValue(
          SecurePendingOnboardingStore(
            storage: platform,
            queue: OnboardingOperationQueue(),
          ),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());
  test(
    'unauthenticated service cannot restore or submit another account operation',
    () async {
      final service = container.read(memberOnboardingServiceProvider);
      await expectLater(
        service.submit(preparedOperation()),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(repository.calls, isEmpty);
      expect(platform.values, isEmpty);
    },
  );
  test(
    'scope comes from authenticated admin context; logout retains recoverable record',
    () async {
      await login();
      final gym = container.read(adminGymProvider)!;
      final scope = OnboardingScope.fromConfig(
        config,
        userId: gym.userId,
        gymId: gym.gymId,
      );
      final operation = preparedOperation(scope: scope);
      final service = container.read(memberOnboardingServiceProvider);
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(
        service.submit(operation),
        throwsA(isA<OnboardingFailure>()),
      );
      await container.read(sessionControllerProvider.notifier).logout();
      await expectLater(
        service.restore(scope),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(platform.values, hasLength(1));
      await login();
      repository.failure = null;
      await service.recover(scope);
      expect(repository.calls.map((call) => call.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );
  test(
    'changing selected authorized gym cannot replay an operation in another gym',
    () async {
      await login();
      final service = container.read(memberOnboardingServiceProvider);
      final operation = preparedOperation();
      repository.failure = const OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
      );
      await expectLater(
        service.submit(operation),
        throwsA(isA<OnboardingFailure>()),
      );
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await expectLater(
        service.recover(operation.scope),
        throwsA(isA<OnboardingFailure>()),
      );
      expect(repository.calls, hasLength(1));
      expect(platform.values, hasLength(1));
    },
  );
  test(
    'Riverpod service replacement preserves the queue and cancelled v2 history',
    () async {
      await login();
      final gym = container.read(adminGymProvider)!;
      final scope = OnboardingScope.fromConfig(
        config,
        userId: gym.userId,
        gymId: gym.gymId,
      );
      final operation = preparedOperation(scope: scope);
      repository.gate = Completer<OnboardingResult>();
      final previous = container.read(memberOnboardingServiceProvider);
      final pending = previous.submit(operation);
      for (var n = 0; n < 100 && repository.calls.isEmpty; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repository.calls, hasLength(1));
      container.invalidate(memberOnboardingServiceProvider);
      final next = container.read(memberOnboardingServiceProvider);
      expect(identical(previous, next), isFalse);
      expect(repository.calls.single.cancel!.isCancelled, isTrue);
      final recovery = next.recover(scope);
      final assertion = expectLater(pending, throwsA(isA<OnboardingFailure>()));
      repository.gate!.complete(
        OnboardingResult.fromJson(onboardingResultJson(operation.request)),
      );
      repository.gate = null;
      await assertion;
      await recovery;
      final restored = (await next.restore(scope))!;
      expect(restored.version, 2);
      expect(restored.attempts.map((a) => a.outcome), [
        OnboardingAttemptOutcome.unresolved,
        OnboardingAttemptOutcome.confirmed,
      ]);
      expect(repository.calls.map((c) => c.key).toSet(), {
        operation.idempotencyKey,
      });
    },
  );
}
