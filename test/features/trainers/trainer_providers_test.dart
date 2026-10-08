import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/trainers/data/trainer_failure.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import 'package:gym_management_app/features/trainers/providers/trainer_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'trainer_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeTrainerRepository repository;
  late FakeAuthApi api;
  setUp(() {
    api = FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]);
    repository = FakeTrainerRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        trainerRepositoryProvider.overrideWithValue(repository),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> login() => container
      .read(sessionControllerProvider.notifier)
      .login(email: 'person@example.invalid', password: syntheticCredential());
  TrainerScope scope([String id = trainerId]) =>
      scopeFor(container.read(adminGymProvider)!, id);
  test('unauthenticated list never calls API', () async {
    expect(await container.read(trainersProvider.future), isNull);
    expect(repository.listCalls, isEmpty);
  });
  test('loading to typed trainer page', () async {
    await login();
    repository.delayLists = true;
    final result = container.read(trainersProvider.future);
    expect(container.read(trainersProvider).isLoading, isTrue);
    repository.pendingLists.single.complete(
      TrainersPage([
        TrainerProfile.fromJson(trainerJson()),
      ], Pagination.fromJson({'page': 1, 'limit': 20, 'total': 1})),
    );
    expect((await result)!.trainers.single.name, 'Pat Lee');
    expect(container.read(trainersProvider).hasValue, isTrue);
  });
  test('empty results are successful data', () async {
    await login();
    repository.empty = true;
    expect((await container.read(trainersProvider.future))!.trainers, isEmpty);
  });
  test('failure then retry and refresh', () async {
    await login();
    repository.failure = const TrainerFailure('Offline');
    await expectLater(
      container.read(trainersProvider.future),
      throwsA(isA<TrainerFailure>()),
    );
    expect(container.read(trainersProvider).hasError, isTrue);
    repository.failure = null;
    await container.read(trainersProvider.notifier).reload();
    await container.read(trainersProvider.notifier).reload();
    expect(repository.listCalls.length, 3);
  });
  test('search/filter resets page; pagination uses server requests', () async {
    await login();
    await container.read(trainersProvider.future);
    container.read(trainerQueryProvider.notifier).page(2);
    await container.read(trainersProvider.future);
    container
        .read(trainerQueryProvider.notifier)
        .apply(search: ' Alex ', status: TrainerStatus.inactive);
    await container.read(trainersProvider.future);
    expect(repository.listCalls[1].query.page, 2);
    expect(repository.listCalls.last.query.toParameters(), {
      'page': '1',
      'limit': '20',
      'search': 'Alex',
      'status': 'inactive',
    });
  });
  test('gym switch resets filters and disallows old trainer reads', () async {
    await login();
    final old = scope();
    container.read(trainerQueryProvider.notifier).apply(search: 'Alex');
    await container.read(trainersProvider.future);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await container.read(trainersProvider.future);
    expect(repository.listCalls.last.gymId, gymB);
    expect(repository.listCalls.last.query.search, isEmpty);
    expect(await container.read(trainerDetailProvider(old).future), isNull);
    expect(repository.operations, isEmpty);
  });
  test('logout clears list cache and trainer scope', () async {
    await login();
    final old = scope();
    await container.read(trainersProvider.future);
    await container.read(sessionControllerProvider.notifier).logout();
    expect(await container.read(trainersProvider.future), isNull);
    expect(await container.read(trainerProfileProvider(old).future), isNull);
  });
  test('stale list response cannot replace latest search', () async {
    await login();
    repository.delayLists = true;
    container.listen(trainersProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(trainerQueryProvider.notifier).apply(search: 'Latest');
    final latest = container.read(trainersProvider.future);
    await Future<void>.delayed(Duration.zero);
    repository.pendingLists[1].complete(
      TrainersPage(
        [],
        Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
      ),
    );
    await latest;
    repository.pendingLists[0].complete(
      TrainersPage([
        TrainerProfile.fromJson(trainerJson()),
      ], Pagination.fromJson({'page': 1, 'limit': 20, 'total': 1})),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(trainersProvider).asData!.value!.trainers, isEmpty);
  });

  test(
    'creation saves once, prevents duplicate submits, refreshes list',
    () async {
      await login();
      await container.read(trainersProvider.future);
      repository.saveGate = Completer<TrainerProfile>();
      final current = scope('');
      container.listen(trainerMutationProvider(current), (_, _) {});
      final controller = container.read(
        trainerMutationProvider(current).notifier,
      );
      final saving = controller.save(draft());
      expect(
        container.read(trainerMutationProvider(current)).isLoading,
        isTrue,
      );
      expect(await controller.save(draft()), isNull);
      expect(repository.writes.length, 1);
      repository.saveGate!.complete(TrainerProfile.fromJson(trainerJson()));
      expect((await saving)!.id, trainerId);
      await container.read(trainersProvider.future);
      expect(repository.listCalls.length, 2);
    },
  );
  test('update error is rendered without fabricated local trainer', () async {
    await login();
    final current = scope();
    container.listen(trainerMutationProvider(current), (_, _) {});
    repository.failure = const TrainerFailure('Duplicate code');
    expect(
      await container
          .read(trainerMutationProvider(current).notifier)
          .save(draft()),
      isNull,
    );
    expect(container.read(trainerMutationProvider(current)).hasError, isTrue);
    expect(repository.operations.single, 'update:$gymA:$trainerId');
  });
  test('pending save cannot publish into another gym', () async {
    await login();
    final current = scope('');
    repository.saveGate = Completer<TrainerProfile>();
    container.listen(trainerMutationProvider(current), (_, _) {});
    final saving = container
        .read(trainerMutationProvider(current).notifier)
        .save(draft());
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await Future<void>.delayed(Duration.zero);
    repository.saveGate!.complete(TrainerProfile.fromJson(trainerJson()));
    expect(await saving, isNull);
    expect(
      container.read(trainerMutationProvider(current)).asData!.value,
      isNull,
    );
    expect(
      await container
          .read(trainerMutationProvider(current).notifier)
          .save(draft()),
      isNull,
    );
    expect(repository.writes.length, 1);
  });
}
