import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/personal_training/trainer_clients.dart';
import 'package:gym_management_app/features/personal_training/trainer_home_page.dart';
import 'package:gym_management_app/features/trainers/data/trainer_failure.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import 'package:gym_management_app/features/trainers/presentation/trainer_app_access.dart';

import '../trainers/trainer_fakes.dart';
import 'pt_fakes.dart';

class _FakeAccess implements TrainerAccessRepository {
  final calls = <String>[];
  TrainerFailure? failure;
  @override
  Future<void> giveAccess(
    String gymId,
    TrainerProfile trainer, {
    required String email,
    required String password,
  }) async {
    calls.add('$gymId:${trainer.id}:$email');
    if (failure != null) throw failure!;
  }
}

class _FakeClients implements TrainerClientRepository {
  final mineRows = <TrainerClient>[];
  final calls = <String>[];
  static const asha = TrainerClient(
    memberId: 'm2',
    memberCode: 'ME002',
    name: 'Asha Rao',
  );
  @override
  Future<List<TrainerClient>> mine(String gymId) async => List.of(mineRows);
  @override
  Future<List<TrainerClient>> search(String gymId, String text) async {
    calls.add('search:$text');
    return [asha];
  }

  @override
  Future<void> takeOn(String gymId, String memberId) async {
    calls.add('take:$memberId');
    mineRows.add(asha);
  }

  @override
  Future<void> release(String gymId, String memberId) async {
    calls.add('release:$memberId');
    mineRows.removeWhere((row) => row.memberId == memberId);
  }
}

Widget _home(FakePtRepository pt, _FakeClients clients) => ptHarness(
  pt,
  const TrainerHomePage(),
  overrides: [trainerClientRepositoryProvider.overrideWithValue(clients)],
);

void main() {
  test('app access shows only whether a login is linked', () {
    expect(TrainerProfile.fromJson(trainerJson()).hasAppAccess, isFalse);
    expect(
      TrainerProfile.fromJson({...trainerJson(), 'userId': 'u1'}).hasAppAccess,
      isTrue,
    );
  });

  testWidgets('trainer home lists PT clients and logs a session in one tap', (
    tester,
  ) async {
    final repository = FakePtRepository(packages: [ptJson(money: false)]);
    await tester.pumpWidget(_home(repository, _FakeClients()));
    await tester.pumpAndSettle();
    expect(find.text('Riya Shah'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.textContaining('₹'), findsNothing);
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['session:null']);
    expect(find.textContaining('Logged for Riya Shah'), findsOneWidget);
  });

  testWidgets(
    'owner gives a trainer app access with a strong temporary password',
    (tester) async {
      final access = _FakeAccess()
        ..failure = const TrainerFailure(
          'That email already has access to this gym. Use another email.',
        );
      var granted = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerAccessRepositoryProvider.overrideWithValue(access),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: TrainerAppAccessCard(
                gymId: gymId,
                trainer: TrainerProfile.fromJson(trainerJson()),
                onGranted: () => granted++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Give app access'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('trainer-access-email')),
        'pat@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('trainer-access-password')),
        'short',
      );
      await tester.tap(find.text('Give access'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 15 characters'), findsOneWidget);
      expect(access.calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('trainer-access-password')),
        'quiet-river-lamp-42',
      );
      await tester.tap(find.text('Give access'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already has access'), findsOneWidget);
      access.failure = null;
      await tester.tap(find.text('Give access'));
      await tester.pumpAndSettle();
      expect(access.calls.last, '$gymId:$trainerId:pat@example.com');
      expect(granted, 1);
    },
  );

  testWidgets('trainer takes on any member and can remove them again', (
    tester,
  ) async {
    final clients = _FakeClients();
    await tester.pumpWidget(_home(FakePtRepository(packages: []), clients));
    await tester.pumpAndSettle();
    expect(find.text('My members · 0'), findsOneWidget);
    await tester.ensureVisible(find.text('Take on'));
    await tester.tap(find.text('Take on'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('take-on-search')), 'as');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha Rao'));
    await tester.pumpAndSettle();
    expect(clients.calls, ['search:as', 'take:m2']);
    expect(find.text('My members · 1'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Remove from my members'));
    await tester.tap(find.byTooltip('Remove from my members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member'));
    await tester.pumpAndSettle();
    expect(clients.calls.last, 'release:m2');
    expect(find.text('My members · 0'), findsOneWidget);
  });
}
