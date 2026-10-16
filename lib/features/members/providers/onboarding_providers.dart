import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/member_onboarding_repository.dart';
import '../data/member_onboarding_service.dart';
import '../data/pending_onboarding_store.dart';
import '../data/onboarding_secure_storage.dart';
import '../models/pending_onboarding.dart';

final memberOnboardingRepositoryProvider = Provider<MemberOnboardingRepository>(
  (ref) =>
      DioMemberOnboardingRepository(ref.watch(authenticatedApiClientProvider)),
);
final onboardingStorageQueueProvider = Provider(
  (ref) => OnboardingOperationQueue(),
);
final onboardingSubmissionQueueProvider = Provider(
  (ref) => OnboardingOperationQueue(),
);
final pendingOnboardingStoreProvider = Provider<PendingOnboardingStore>(
  (ref) => SecurePendingOnboardingStore(
    storage: const OnboardingSecureStorage(),
    queue: ref.watch(onboardingStorageQueueProvider),
  ),
);

final memberOnboardingServiceProvider = Provider<MemberOnboardingService>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  final auth = ref.watch(authRepositoryProvider);
  final service = MemberOnboardingService(
    repository: ref.watch(memberOnboardingRepositoryProvider),
    store: ref.watch(pendingOnboardingStoreProvider),
    queue: ref.watch(onboardingSubmissionQueueProvider),
    isAuthorized: (scope) {
      if (!ref.mounted ||
          !identical(ref.read(authRepositoryProvider), auth) ||
          !identical(ref.read(appConfigProvider), config)) {
        return false;
      }
      final state = auth.state;
      final authenticated =
          state is SessionAuthenticated ||
          state is SessionLoading &&
              state.operation == SessionOperation.refreshing;
      final gym = ref.read(adminGymProvider);
      if (state is SessionAuthenticated &&
          (state.identity.user.id != gym?.userId ||
              state.identity.user.status != AccountStatus.active ||
              !state.identity.gymAccess.any(
                (grant) =>
                    grant.gymId == gym?.gymId &&
                    grant.role == AuthRole.admin &&
                    grant.status == AccountStatus.active,
              ))) {
        return false;
      }
      return authenticated &&
          gym != null &&
          config.apiBaseUrl != null &&
          scope.matches(
            OnboardingScope.fromConfig(
              config,
              userId: gym.userId,
              gymId: gym.gymId,
            ),
          );
    },
  );
  // AuthRepository emits synchronously. Cancel old queued/in-flight requests
  // before a different login can attach its credentials, without changing auth.
  final subscription = auth.changes.listen(
    (_) => service.authorizationChanged(),
  );
  ref.listen(adminGymProvider, (_, _) => service.authorizationChanged());
  ref.onDispose(() {
    service.dispose();
    subscription.cancel();
  });
  return service;
});
