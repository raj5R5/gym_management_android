import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/member_repository.dart';
import 'package:gym_management_app/features/members/data/member_failure.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/presentation/members_page.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import '../auth/auth_fakes.dart';
import '../memberships/payment_fakes.dart';
import 'member_fakes.dart';

String idFor(int value) => value.toRadixString(16).padLeft(24, '0');
MembershipHistory history({int balance = 50000}) =>
    MembershipHistory.fromResponse(
      {
        ...historyJson(populated: true),
        'currentMembership': debtJson(balance: balance),
        'subscriptions': [debtJson(balance: balance)],
      },
      {'page': 1, 'limit': 20, 'total': 1},
    );

class _FailingSecondPage extends DueMembersFake {
  @override
  Future<MembershipHistory> memberships(String gymId, String id, int page) {
    if (page == 2) throw const MemberFailure('History page unavailable.');
    return super.memberships(gymId, id, page);
  }
}

void main() {
  late ProviderContainer container;
  late FakeMemberRepository repository;
  setUp(() async {
    repository = FakeMemberRepository();
    container = ProviderContainer(
      overrides: [
        authApiServiceProvider.overrideWithValue(
          FakeAuthApi()..identity = adminIdentity(gyms: [gymA, gymB]),
        ),
        credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
        memberRepositoryProvider.overrideWithValue(repository),
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
  MemberScope scope() => scopeFor(container.read(adminGymProvider)!, memberId);

  test('unchanged filters and current page do not refetch members', () async {
    await container.read(membersProvider.future);
    container.read(memberQueryProvider.notifier).apply(search: '');
    container.read(memberQueryProvider.notifier).page(1);
    await container.read(membersProvider.future);
    expect(repository.listCalls.length, 1);
    container.read(memberQueryProvider.notifier).apply(search: ' Alex ');
    await container.read(membersProvider.future);
    container.read(memberQueryProvider.notifier).apply(search: 'Alex');
    await container.read(membersProvider.future);
    expect(repository.listCalls.length, 2);
    container.read(memberQueryProvider.notifier).page(2);
    await container.read(membersProvider.future);
    container.read(memberQueryProvider.notifier).apply(search: 'Alex');
    await container.read(membersProvider.future);
    expect(repository.listCalls.last.query.page, 1);
    expect(repository.listCalls.length, 4);
  });

  test(
    'overlapping directory reloads share a single replacement request',
    () async {
      await container.read(membersProvider.future);
      repository.delayLists = true;
      final first = container.read(membersProvider.notifier).reload();
      final second = container.read(membersProvider.notifier).reload();
      expect(identical(first, second), isTrue);
      repository.pendingLists.single.complete(
        MembersPage(
          [],
          Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
        ),
      );
      await Future.wait([first, second]);
      expect(repository.listCalls.length, 2);
    },
  );

  test(
    'full history and paginated history share an identical active page read',
    () async {
      repository.historyGate = Completer<MembershipHistory>();
      final selected = scope();
      final full = container.read(memberMembershipsProvider(selected).future);
      final page = container.read(
        memberHistoryProvider((scope: selected, page: 1)).future,
      );
      expect(repository.operations, ['history:1']);
      repository.historyGate!.complete(history());
      expect((await full)!.single.payments!.balancePaise, 50000);
      expect((await page)!.subscriptions.single.payments!.balancePaise, 50000);
    },
  );

  test(
    'invalidation starts a fresh balance read and an older response cannot replace it',
    () async {
      final selected = scope();
      final old = Completer<MembershipHistory>();
      repository.historyGate = old;
      final listener = container.listen(
        memberMembershipsProvider(selected),
        (_, _) {},
      );
      addTearDown(listener.close);
      container.read(memberMembershipsProvider(selected).future);
      final latest = Completer<MembershipHistory>();
      repository.historyGate = latest;
      container.invalidate(memberMembershipsProvider(selected));
      final fresh = container.read(memberMembershipsProvider(selected).future);
      expect(repository.operations, ['history:1', 'history:1']);
      latest.complete(history(balance: 100));
      expect((await fresh)!.single.payments!.balancePaise, 100);
      old.complete(history(balance: 900));
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(memberMembershipsProvider(selected))
            .requireValue!
            .single
            .payments!
            .balancePaise,
        100,
      );
    },
  );

  test(
    'a new login for the same account never joins an old session read',
    () async {
      final selected = scope();
      final old = Completer<MembershipHistory>();
      repository.historyGate = old;
      final listener = container.listen(
        memberMembershipsProvider(selected),
        (_, _) {},
      );
      addTearDown(listener.close);
      container.read(memberMembershipsProvider(selected).future);
      await container.read(sessionControllerProvider.notifier).logout();
      final latest = Completer<MembershipHistory>();
      repository.historyGate = latest;
      await container
          .read(sessionControllerProvider.notifier)
          .login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
      final fresh = container.read(memberMembershipsProvider(scope()).future);
      expect(repository.operations, ['history:1', 'history:1']);
      latest.complete(history(balance: 200));
      expect((await fresh)!.single.payments!.balancePaise, 200);
      old.complete(history(balance: 900));
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(memberMembershipsProvider(scope()))
            .requireValue!
            .single
            .payments!
            .balancePaise,
        200,
      );
    },
  );

  test(
    'gym changes isolate histories and reject an outstanding old scope',
    () async {
      final previous = scope();
      final old = Completer<MembershipHistory>();
      repository.historyGate = old;
      final listener = container.listen(
        memberMembershipsProvider(previous),
        (_, _) {},
      );
      addTearDown(listener.close);
      container.read(memberMembershipsProvider(previous).future);
      container.read(adminGymProvider.notifier).selectGym(gymB);
      expect(
        await container.read(memberMembershipsProvider(previous).future),
        isNull,
      );
      repository.historyGate = Completer<MembershipHistory>()
        ..complete(history(balance: 300));
      expect(
        (await container.read(
          memberMembershipsProvider(scope()).future,
        ))!.single.payments!.balancePaise,
        300,
      );
      old.complete(history(balance: 900));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(memberMembershipsProvider(previous)).requireValue,
        isNull,
      );
    },
  );

  test('failed history flights are not reused on explicit retry', () async {
    final selected = scope();
    repository.historyGate = Completer<MembershipHistory>();
    final first = container.read(memberMembershipsProvider(selected).future);
    final failure = expectLater(first, throwsA(isA<StateError>()));
    repository.historyGate!.completeError(StateError('synthetic failure'));
    await failure;
    repository.historyGate = Completer<MembershipHistory>()
      ..complete(history());
    container.invalidate(memberMembershipsProvider(selected));
    expect(
      (await container.read(
        memberMembershipsProvider(selected).future,
      ))!.length,
      1,
    );
    expect(repository.operations, ['history:1', 'history:1']);
  });

  testWidgets(
    '20-member directory makes 21 Dio requests, no summaries, and refreshes once',
    (tester) async {
      final requests = <RequestOptions>[];
      final client = Dio(
        BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'),
      );
      client.httpClientAdapter = CallbackAdapter((request) {
        requests.add(request);
        if (request.path.endsWith('/members')) {
          return jsonResponse({
            'success': true,
            'data': [
              for (var i = 0; i < 20; i++)
                {...profileJson(firstName: 'Person $i'), 'id': idFor(100 + i)},
            ],
            'meta': {
              'pagination': {'page': 1, 'limit': 20, 'total': 20},
            },
          });
        }
        if (request.path.endsWith('/memberships')) {
          final id = request.path.split('/')[3];
          return jsonResponse({
            'success': true,
            'data': {
              'member': {'id': id},
              'currentMembership': null,
              'subscriptions': [],
            },
            'meta': {
              'pagination': {'page': 1, 'limit': 20, 'total': 0},
            },
          });
        }
        fail('Unexpected request: ${request.path}');
      });
      final app = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.fromValues()),
          authApiServiceProvider.overrideWithValue(
            FakeAuthApi()..identity = adminIdentity(),
          ),
          credentialStorageProvider.overrideWithValue(FakeCredentialStorage()),
          memberRepositoryProvider.overrideWithValue(
            DioMemberRepository(client),
          ),
        ],
      );
      addTearDown(() {
        app.dispose();
        client.close();
      });
      await app
          .read(sessionControllerProvider.notifier)
          .login(
            email: 'person@example.invalid',
            password: syntheticCredential(),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: app,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: MembersPageView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.path.endsWith('/members')).length, 1);
      expect(requests.where((r) => r.path.endsWith('/memberships')).length, 20);
      expect(requests.where((r) => r.path.endsWith('/summary')), isEmpty);
      expect(requests.length, 21);
      await tester.pump();
      expect(requests.length, 21);
      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final first = indicator.onRefresh();
      final second = indicator.onRefresh();
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      expect(requests.where((r) => r.path.endsWith('/members')).length, 2);
      expect(requests.where((r) => r.path.endsWith('/memberships')).length, 40);
      expect(requests.length, 42);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in ['historical', 'expired', 'future', 'incomplete']) {
    testWidgets(
      'directory preserves $scenario debt semantics without a summary',
      (tester) async {
        final members = scenario == 'incomplete'
            ? _FailingSecondPage()
            : DueMembersFake();
        members.debts[memberId] = switch (scenario) {
          'historical' || 'incomplete' => [
            debtJson(balance: 0),
            for (var i = 0; i < 19; i++)
              debtJson(id: idFor(500 + i), balance: 0, status: 'expired'),
            debtJson(id: idFor(600), balance: 70000, status: 'expired'),
          ],
          'expired' => [debtJson(balance: 50000, status: 'expired')],
          _ => [
            debtJson(id: idFor(601), balance: 20000)..addAll({
              'isCurrentlyActive': false,
              'startDate': '2027-01-01',
              'endDate': '2027-01-31',
            }),
            debtJson(balance: 0),
            debtJson(id: idFor(602), balance: 70000, status: 'expired'),
            debtJson(id: idFor(603), balance: 140000, status: 'cancelled'),
          ],
        };
        final app = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.fromValues()),
            authApiServiceProvider.overrideWithValue(
              FakeAuthApi()..identity = adminIdentity(),
            ),
            credentialStorageProvider.overrideWithValue(
              FakeCredentialStorage(),
            ),
            memberRepositoryProvider.overrideWithValue(members),
          ],
        );
        addTearDown(app.dispose);
        await app
            .read(sessionControllerProvider.notifier)
            .login(
              email: 'person@example.invalid',
              password: syntheticCredential(),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: app,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: MembersPageView()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          members.operations.where((value) => value.startsWith('summary:')),
          isEmpty,
        );
        expect(find.text('Fully Paid'), findsNothing);
        if (scenario == 'incomplete') {
          expect(find.text('Membership details unavailable'), findsOneWidget);
          expect(find.textContaining('due'), findsNothing);
        } else {
          expect(
            find.text(switch (scenario) {
              'historical' => '₹700.00 due',
              'expired' => '₹500.00 due',
              _ => '₹900.00 due',
            }),
            findsOneWidget,
          );
          if (scenario == 'expired') {
            expect(find.text('Expired'), findsOneWidget);
          }
          if (scenario == 'historical') {
            expect(
              members.operations
                  .where((value) => value.startsWith('memberships:'))
                  .length,
              2,
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
