import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../data/trainer_failure.dart';
import '../data/trainer_repository.dart';
import '../models/trainer_draft.dart';
import '../models/trainer_models.dart';

typedef TrainerScope = ({String userId, String gymId, String trainerId});
TrainerScope scopeFor(AdminGymContext context, String trainerId) =>
    (userId: context.userId, gymId: context.gymId, trainerId: trainerId);
bool matchesScope(AdminGymContext? context, TrainerScope scope) =>
    context?.userId == scope.userId && context?.gymId == scope.gymId;
final trainerRepositoryProvider = Provider<TrainerRepository>(
  (ref) => DioTrainerRepository(ref.watch(authenticatedApiClientProvider)),
);

class TrainerQueryController extends Notifier<TrainerListQuery> {
  @override
  TrainerListQuery build() {
    ref.watch(
      adminGymProvider,
    ); // Reset filters/pages on tenant or account change.
    return TrainerListQuery();
  }

  void apply({required String search, TrainerStatus? status}) =>
      state = TrainerListQuery(search: search, status: status);
  void page(int page) => state = state.withPage(page);
}

final trainerQueryProvider =
    NotifierProvider<TrainerQueryController, TrainerListQuery>(
      TrainerQueryController.new,
    );

class TrainersController extends AsyncNotifier<TrainersPage?> {
  @override
  Future<TrainersPage?> build() async {
    final context = ref.watch(adminGymProvider);
    final query = ref.watch(trainerQueryProvider);
    if (context == null) return null;
    return ref.watch(trainerRepositoryProvider).list(context.gymId, query);
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final trainersProvider =
    AsyncNotifierProvider<TrainersController, TrainersPage?>(
      TrainersController.new,
      retry: (_, _) => null,
    );
final trainerProfileProvider = FutureProvider.autoDispose
    .family<TrainerProfile?, TrainerScope>((ref, scope) {
      if (!matchesScope(ref.watch(adminGymProvider), scope)) return null;
      return ref
          .watch(trainerRepositoryProvider)
          .get(scope.gymId, scope.trainerId);
    }, retry: (_, _) => null);
final trainerDetailProvider = FutureProvider.autoDispose
    .family<TrainerProfile?, TrainerScope>((ref, scope) {
      if (!matchesScope(ref.watch(adminGymProvider), scope)) return null;
      return ref
          .watch(trainerRepositoryProvider)
          .get(scope.gymId, scope.trainerId);
    }, retry: (_, _) => null);

class TrainerMutationController extends AsyncNotifier<TrainerProfile?> {
  TrainerMutationController(this.scope);
  final TrainerScope scope;
  bool _busy = false;
  @override
  TrainerProfile? build() {
    ref.watch(adminGymProvider);
    return null;
  }

  bool _current() =>
      ref.mounted &&
      matchesScope(ref.read(adminGymProvider), scope) &&
      ref.read(sessionControllerProvider) is SessionAuthenticated;
  Future<TrainerProfile?> save(TrainerDraft draft) async {
    if (_busy || !_current()) return null;
    _busy = true;
    state = const AsyncLoading();
    try {
      final repository = ref.read(trainerRepositoryProvider);
      final saved = scope.trainerId.isEmpty
          ? await repository.create(scope.gymId, draft)
          : await repository.update(scope.gymId, scope.trainerId, draft);
      // A sent server mutation cannot be recalled, but it must never update a
      // different account/gym's presentation or cache after navigation/logout.
      if (!_current()) return null;
      state = AsyncData(saved);
      ref.invalidate(trainersProvider);
      ref.invalidate(dashboardProvider);
      if (scope.trainerId.isNotEmpty) {
        ref.invalidate(trainerDetailProvider(scope));
      }
      return saved;
    } catch (error, stack) {
      if (_current()) {
        state = AsyncError(
          error is TrainerFailure
              ? error
              : const TrainerFailure(
                  'Trainer could not be saved. Please try again.',
                ),
          stack,
        );
      }
      return null;
    } finally {
      _busy = false;
    }
  }
}

final trainerMutationProvider = AsyncNotifierProvider.autoDispose
    .family<TrainerMutationController, TrainerProfile?, TrainerScope>(
      TrainerMutationController.new,
      retry: (_, _) => null,
    );
