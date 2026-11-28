import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/gym_join/gym_join.dart';
import 'package:gym_management_app/features/gym_join/join_gym_page.dart';
import 'package:gym_management_app/features/gym_join/join_requests_page.dart';

Map<String, dynamic> requestJson({
  String id = 'r1',
  String status = 'pending',
  String role = 'member',
  String? reason,
}) => {
  'id': id,
  'gymId': 'g1',
  'gymName': 'Iron Den',
  'role': role,
  'name': 'Asha Verma',
  'phone': '+919123456780',
  'status': status,
  'createdAt': '2026-11-28T10:00:00Z',
  'reason': reason,
};

class _Repository extends GymJoinRepository {
  _Repository() : super(Dio());
  final calls = <String>[];
  List<JoinRequest> requests = [];
  int linkedOnCheck = 0;
  JoinOutcome outcome = JoinPending(JoinRequest.fromJson(requestJson()));

  @override
  Future<String> lookup(String code) async {
    calls.add('lookup:$code');
    if (code != 'ABC234') {
      throw const GymJoinFailure(
        'No gym has that code. Check it with your gym.',
      );
    }
    return 'Iron Den';
  }

  @override
  Future<JoinOutcome> ask({
    required String code,
    required JoinRole role,
    required String name,
  }) async {
    calls.add('ask:$code:${role.wire}:$name');
    return outcome;
  }

  @override
  Future<List<JoinRequest>> mine() async => requests;
  @override
  Future<void> cancel(String id) async => calls.add('cancel:$id');
  @override
  Future<int> checkAgain() async {
    calls.add('check');
    return linkedOnCheck;
  }

  @override
  Future<({String code, String gymName})> joinCode(String gymId) async =>
      (code: 'ABC234', gymName: 'Iron Den');
  @override
  Future<List<JoinRequest>> pending(String gymId) async => requests;
  @override
  Future<void> approve(String gymId, String id) async {
    calls.add('approve:$id');
    requests = [];
  }

  @override
  Future<void> reject(String gymId, String id, {String? reason}) async {
    calls.add('reject:$id:${reason ?? ''}');
    requests = [];
  }
}

class _Session extends SessionController {
  int refreshes = 0;
  @override
  SessionState build() => SessionAuthenticated(
    AuthIdentity(
      user: const AuthUser(
        id: 'u1',
        status: AccountStatus.active,
        displayName: 'Asha Verma',
        phone: '+919123456780',
        phoneVerified: true,
        hasPassword: false,
      ),
      gymAccess: const [],
    ),
  );
  @override
  Future<void> refreshSession() async => refreshes += 1;
}

void main() {
  test('join requests read both sides of the API', () {
    final request = JoinRequest.fromJson(
      requestJson(status: 'rejected', reason: 'Not here', role: 'trainer'),
    );
    expect(request.status, JoinStatus.rejected);
    expect(request.role, JoinRole.trainer);
    expect(request.reason, 'Not here');
  });

  Future<(_Repository, _Session)> pump(WidgetTester tester, Widget page) async {
    final repository = _Repository();
    final session = _Session();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gymJoinRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(() => session),
          adminGymProvider.overrideWithBuild(
            (ref, _) => (userId: 'u1', gymId: 'g1'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repository, session);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('someone with no gym finds the gym by code and asks to join', (
    tester,
  ) async {
    final (repository, _) = await pump(tester, const JoinGymPage());
    expect(find.text('No requests yet.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('gym-code')), 'ZZZ999');
    await tap(tester, find.text('Find gym'));
    expect(
      find.text('No gym has that code. Check it with your gym.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('gym-code')), 'abc234');
    await tap(tester, find.text('Find gym'));
    expect(find.text('Join Iron Den as'), findsOneWidget);
    await tap(tester, find.text('Trainer'));
    repository.requests = [JoinRequest.fromJson(requestJson(role: 'trainer'))];
    await tap(tester, find.text('Send request'));
    expect(repository.calls.last, 'ask:abc234:trainer:Asha Verma');
    expect(find.text('Iron Den · Trainer'), findsOneWidget);
    expect(find.text('Waiting for the owner'), findsOneWidget);
    await tap(tester, find.text('Cancel'));
    expect(repository.calls.last, 'cancel:r1');
  });

  testWidgets('a code for a gym that already added the number links at once', (
    tester,
  ) async {
    final (repository, session) = await pump(tester, const JoinGymPage());
    repository.outcome = const JoinLinked('Iron Den');
    await tester.enterText(find.byKey(const ValueKey('gym-code')), 'ABC234');
    await tap(tester, find.text('Find gym'));
    await tap(tester, find.text('Send request'));
    expect(find.text('You are in Iron Den.'), findsOneWidget);
    expect(session.refreshes, 1);
  });

  testWidgets('check again refreshes the session only when a gym linked', (
    tester,
  ) async {
    final (repository, session) = await pump(tester, const JoinGymPage());
    await tap(tester, find.byKey(const ValueKey('check-again')));
    expect(find.text('No gym has added your number yet.'), findsOneWidget);
    expect(session.refreshes, 0);
    repository.linkedOnCheck = 1;
    await tap(tester, find.byKey(const ValueKey('check-again')));
    expect(session.refreshes, 1);
  });

  testWidgets('a rejected request shows the reason', (tester) async {
    final repository = _Repository()
      ..requests = [
        JoinRequest.fromJson(
          requestJson(status: 'rejected', reason: 'Gym is full'),
        ),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gymJoinRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(_Session.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: JoinGymPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not accepted: Gym is full'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('the owner sees the gym code and approves a request', (
    tester,
  ) async {
    final repository = _Repository()
      ..requests = [JoinRequest.fromJson(requestJson())];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gymJoinRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(_Session.new),
          adminGymProvider.overrideWithBuild(
            (ref, _) => (userId: 'u1', gymId: 'g1'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: JoinRequestsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gym-join-code')), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.text('Asha Verma'), findsOneWidget);
    await tap(tester, find.text('Approve'));
    expect(find.text('Add Asha Verma?'), findsOneWidget);
    await tap(tester, find.text('Approve').last);
    expect(repository.calls, ['approve:r1']);
    expect(find.text('Asha Verma added.'), findsOneWidget);
    expect(find.textContaining('No one is waiting'), findsOneWidget);
  });

  testWidgets('the owner declines with a reason the asker will see', (
    tester,
  ) async {
    final repository = _Repository()
      ..requests = [JoinRequest.fromJson(requestJson())];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gymJoinRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(_Session.new),
          adminGymProvider.overrideWithBuild(
            (ref, _) => (userId: 'u1', gymId: 'g1'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: JoinRequestsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Decline'));
    await tester.enterText(find.byType(TextField).last, 'Gym is full');
    await tap(tester, find.text('Decline').last);
    expect(repository.calls, ['reject:r1:Gym is full']);
  });
}
