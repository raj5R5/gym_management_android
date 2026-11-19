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
import 'package:gym_management_app/features/members/data/member_overview_repository.dart';
import 'package:gym_management_app/features/members/providers/member_overview_providers.dart';
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
    '20-member list makes one overview request, no per-member reads, and refreshes once',
    (tester) async {
      final requests = <RequestOptions>[];
      final client = Dio(
        BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'),
      );
      client.httpClientAdapter = CallbackAdapter((request) {
        requests.add(request);
        if (request.path.endsWith('/member-overview')) {
          return jsonResponse({
            'success': true,
            'data': {
              'calendar': {'timezone': 'Asia/Kolkata', 'today': '2026-01-11'},
              'counts': {
                'all': 20,
                'active': 20,
                'expiring': 0,
                'dues': 0,
                'expired': 0,
                'none': 0,
              },
              'duesTotalPaise': 0,
              'filter': 'all',
              'data': [
                for (var i = 0; i < 20; i++)
                  {
                    'member': {
                      ...profileJson(firstName: 'Person $i'),
                      'id': idFor(100 + i),
                    },
                    'membership': null,
                    'balancePaise': 0,
                    'dueSubscriptionId': null,
                  },
              ],
              'pagination': {'page': 1, 'limit': 20, 'total': 20},
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
          memberOverviewRepositoryProvider.overrideWithValue(
            DioMemberOverviewRepository(client),
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
      expect(requests.length, 1);
      expect(requests.single.queryParameters['filter'], 'all');
      expect(find.text('Person 0 River'), findsOneWidget);
      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final first = indicator.onRefresh();
      final second = indicator.onRefresh();
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      expect(requests.length, 2, reason: 'overlapping refreshes share one');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
