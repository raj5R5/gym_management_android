import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeMemberRepository repository;
  late FakeAuthApi api;
  setUp(() {
    api = FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]);
    repository = FakeMemberRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        memberRepositoryProvider.overrideWithValue(repository),
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
  MemberScope scope([String id = memberId]) =>
      scopeFor(container.read(adminGymProvider)!, id);
  test('unauthenticated list never calls API', () async {
    expect(await container.read(membersProvider.future), isNull);
    expect(repository.listCalls, isEmpty);
  });
  test('loading to typed member page', () async {
    await login();
    repository.delayLists = true;
    final result = container.read(membersProvider.future);
    expect(container.read(membersProvider).isLoading, isTrue);
    repository.pendingLists.single.complete(
      MembersPage([
        MemberProfile.fromJson(profileJson()),
      ], Pagination.fromJson({'page': 1, 'limit': 20, 'total': 1})),
    );
    expect((await result)!.members.single.name, 'Alex River');
    expect(container.read(membersProvider).hasValue, isTrue);
  });
  test('empty results are successful data', () async {
    await login();
    repository.empty = true;
    expect((await container.read(membersProvider.future))!.members, isEmpty);
  });
  test('failure then retry and refresh', () async {
    await login();
    repository.failure = const MemberFailure('Offline');
    await expectLater(
      container.read(membersProvider.future),
      throwsA(isA<MemberFailure>()),
    );
    expect(container.read(membersProvider).hasError, isTrue);
    repository.failure = null;
    await container.read(membersProvider.notifier).reload();
    await container.read(membersProvider.notifier).reload();
    expect(repository.listCalls.length, 3);
  });
  test('search/filter resets page; pagination uses server requests', () async {
    await login();
    await container.read(membersProvider.future);
    container.read(memberQueryProvider.notifier).page(2);
    await container.read(membersProvider.future);
    container
        .read(memberQueryProvider.notifier)
        .apply(search: ' Alex ', status: MemberStatus.inactive);
    await container.read(membersProvider.future);
    expect(repository.listCalls[1].query.page, 2);
    expect(repository.listCalls.last.query.toParameters(), {
      'page': '1',
      'limit': '20',
      'search': 'Alex',
      'status': 'inactive',
    });
  });
  test('gym switch resets filters and disallows old member reads', () async {
    await login();
    final old = scope();
    container.read(memberQueryProvider.notifier).apply(search: 'Alex');
    await container.read(membersProvider.future);
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await container.read(membersProvider.future);
    expect(repository.listCalls.last.gymId, gymB);
    expect(repository.listCalls.last.query.search, isEmpty);
    expect(await container.read(memberSummaryProvider(old).future), isNull);
    expect(repository.operations, isEmpty);
  });
  test('logout clears list cache and member scope', () async {
    await login();
    final old = scope();
    await container.read(membersProvider.future);
    await container.read(sessionControllerProvider.notifier).logout();
    expect(await container.read(membersProvider.future), isNull);
    expect(await container.read(memberProfileProvider(old).future), isNull);
  });
  test('stale list response cannot replace latest search', () async {
    await login();
    repository.delayLists = true;
    container.listen(membersProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(memberQueryProvider.notifier).apply(search: 'Latest');
    final latest = container.read(membersProvider.future);
    await Future<void>.delayed(Duration.zero);
    repository.pendingLists[1].complete(
      MembersPage(
        [],
        Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
      ),
    );
    await latest;
    repository.pendingLists[0].complete(
      MembersPage([
        MemberProfile.fromJson(profileJson()),
      ], Pagination.fromJson({'page': 1, 'limit': 20, 'total': 1})),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(membersProvider).asData!.value!.members, isEmpty);
  });
  test(
    'gender filter scans later server pages before paginating matches',
    () async {
      await login();
      final data = GenderMemberRepository();
      final provider = ProviderContainer(
        overrides: [
          memberRepositoryProvider.overrideWithValue(data),
          authApiServiceProvider.overrideWithValue(api),
          credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(),
          ),
        ],
      );
      await provider
          .read(sessionControllerProvider.notifier)
          .login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
      addTearDown(provider.dispose);
      provider
          .read(memberQueryProvider.notifier)
          .apply(search: '', gender: 'male');
      final first = (await provider.read(membersProvider.future))!;
      expect(first.pagination.total, 42);
      expect(first.members, hasLength(20));
      expect(first.members.every((member) => member.gender == 'male'), true);
      expect(data.listCalls.map((call) => call.query.page), [1, 2]);
      expect(
        data.listCalls.every(
          (call) =>
              !call.query.toParameters().containsKey('gender') &&
              call.query.status == null,
        ),
        true,
      );
      provider.read(memberQueryProvider.notifier).page(3);
      final last = (await provider.read(membersProvider.future))!;
      expect(last.members.map((member) => member.firstName), [
        'Person 120',
        'Person 123',
      ]);
      expect(last.pagination.page, 3);
      expect(last.pagination.hasNext, false);
      provider
          .read(memberQueryProvider.notifier)
          .apply(search: '', gender: 'female');
      final female = (await provider.read(membersProvider.future))!;
      expect(female.members.every((member) => member.gender == 'female'), true);
      expect(female.pagination.total, 42);
      expect(female.pagination.page, 1);
      provider
          .read(memberQueryProvider.notifier)
          .apply(search: 'Person 124', gender: 'female');
      final search = (await provider.read(membersProvider.future))!;
      expect(search.members.single.firstName, 'Person 124');
      provider.read(memberQueryProvider.notifier).apply(search: '');
      final all = (await provider.read(membersProvider.future))!;
      expect(all.pagination.total, 125);
      expect(all.members.any((member) => member.gender == null), true);
      expect(data.listCalls.last.query.limit, 20);
    },
  );
  test(
    'gender filtering errors never show a partially scanned total',
    () async {
      await login();
      repository.delayLists = true;
      container
          .read(memberQueryProvider.notifier)
          .apply(search: '', gender: 'male');
      final future = container.read(membersProvider.future);
      await Future<void>.delayed(Duration.zero);
      repository.pendingLists.first.complete(
        MembersPage([
          MemberProfile.fromJson({...profileJson(), 'gender': 'male'}),
        ], Pagination.fromJson({'page': 1, 'limit': 100, 'total': 101})),
      );
      await Future<void>.delayed(Duration.zero);
      repository.pendingLists.last.completeError(
        const MemberFailure('Offline'),
      );
      await expectLater(future, throwsA(isA<MemberFailure>()));
      expect(container.read(membersProvider).hasError, true);
      expect(container.read(membersProvider).asData, isNull);
    },
  );
  test(
    'scope change stops an in-flight gender scan before next server page',
    () async {
      await login();
      repository.delayLists = true;
      container
          .read(memberQueryProvider.notifier)
          .apply(search: '', gender: 'male');
      container.listen(membersProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final old = repository.pendingLists.single;
      container.read(adminGymProvider.notifier).selectGym(gymB);
      final current = container.read(membersProvider.future);
      await Future<void>.delayed(Duration.zero);
      repository.pendingLists.last.complete(
        MembersPage(
          [],
          Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
        ),
      );
      await current;
      old.complete(
        MembersPage(
          [],
          Pagination.fromJson({'page': 1, 'limit': 100, 'total': 101}),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        repository.listCalls.where((call) => call.gymId == gymA),
        hasLength(1),
      );
      expect(container.read(memberQueryProvider).gender, isNull);
      expect(container.read(membersProvider).asData!.value!.members, isEmpty);
    },
  );
  test('summary/profile/history/membership reads use current scope', () async {
    await login();
    final current = scope();
    repository.populated = true;
    expect(
      (await container.read(memberSummaryProvider(current).future))!.member.id,
      memberId,
    );
    expect(
      (await container.read(memberProfileProvider(current).future))!.gymId,
      gymA,
    );
    expect(
      (await container.read(
        memberHistoryProvider((scope: current, page: 2)).future,
      ))!.pagination.page,
      2,
    );
    expect(
      (await container.read(
        membershipDetailProvider((
          scope: current,
          subscriptionId: subscriptionId,
        )).future,
      ))!.subscription.status,
      'cancelled',
    );
  });
  test(
    'onboarding saves once, prevents duplicate submits, refreshes list',
    () async {
      await login();
      await container.read(membersProvider.future);
      repository.saveGate = Completer<MemberProfile>();
      final current = scope('');
      container.listen(memberMutationProvider(current), (_, _) {});
      final controller = container.read(
        memberMutationProvider(current).notifier,
      );
      final saving = controller.save(draft());
      expect(container.read(memberMutationProvider(current)).isLoading, isTrue);
      expect(await controller.save(draft()), isNull);
      expect(repository.writes.length, 1);
      repository.saveGate!.complete(MemberProfile.fromJson(profileJson()));
      expect((await saving)!.id, memberId);
      await container.read(membersProvider.future);
      expect(repository.listCalls.length, 2);
    },
  );
  test('update error is rendered without fabricated local member', () async {
    await login();
    final current = scope();
    container.listen(memberMutationProvider(current), (_, _) {});
    repository.failure = const MemberFailure('Duplicate code');
    expect(
      await container
          .read(memberMutationProvider(current).notifier)
          .save(draft()),
      isNull,
    );
    expect(container.read(memberMutationProvider(current)).hasError, isTrue);
    expect(repository.operations.single, 'update:$gymA:$memberId');
  });
  test('pending save cannot publish into another gym', () async {
    await login();
    final current = scope('');
    repository.saveGate = Completer<MemberProfile>();
    container.listen(memberMutationProvider(current), (_, _) {});
    final saving = container
        .read(memberMutationProvider(current).notifier)
        .save(draft());
    container.read(adminGymProvider.notifier).selectGym(gymB);
    await Future<void>.delayed(Duration.zero);
    repository.saveGate!.complete(MemberProfile.fromJson(profileJson()));
    expect(await saving, isNull);
    expect(
      container.read(memberMutationProvider(current)).asData!.value,
      isNull,
    );
    expect(
      await container
          .read(memberMutationProvider(current).notifier)
          .save(draft()),
      isNull,
    );
    expect(repository.writes.length, 1);
  });
}
