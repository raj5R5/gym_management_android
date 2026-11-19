import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/app/router/app_routes.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/auth/data/auth_failure.dart';
import 'package:gym_management_app/features/trainers/data/trainer_failure.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import 'package:gym_management_app/features/trainers/providers/trainer_providers.dart';
import '../auth/auth_fakes.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'trainer_fakes.dart';

void main() {
  Future<ProviderContainer> pumpTrainers(
    WidgetTester tester,
    FakeTrainerRepository repository, {
    AuthRole role = AuthRole.admin,
    bool authenticated = true,
  }) async {
    final api = FakeAuthApi()
      ..identity = adminIdentity(gyms: [gymA, gymB], role: role);
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromValues()),
        authApiServiceProvider.overrideWithValue(api),
        credentialStorageProvider.overrideWithValue(
          FakeCredentialStorage()
            ..value = authenticated ? syntheticCredential() : null,
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        trainerRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GymApp(animateDecorations: false),
      ),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go(AppRoutes.trainers);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    return container;
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('Add trainer'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    for (final entry in {
      'trainerCode': 'TR02',
      'firstName': 'Pat',
      'lastName': 'River',
      'phone': '+91 9876543210',
    }.entries) {
      await reveal(tester, find.byKey(ValueKey(entry.key)));
      await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
    }
  }

  testWidgets(
    'real trainer list renders identity/status and server pagination',
    (tester) async {
      final repository = FakeTrainerRepository()..total = 21;
      await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('Pat Lee'), findsOneWidget);
      expect(find.textContaining('TR01 · +91 9876543210'), findsOneWidget);
      expect(find.text('Page 1 · 21 total'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.page, 2);
      expect(find.text('Page 2 · 21 total'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(repository.listCalls.last.query.page, 1);
    },
  );
  testWidgets('empty list is actionable', (tester) async {
    await pumpTrainers(tester, FakeTrainerRepository()..empty = true);
    await tester.pumpAndSettle();
    expect(
      find.text('No trainers yet. Add your first trainer.'),
      findsOneWidget,
    );
    expect(find.text('Add trainer'), findsOneWidget);
  });
  testWidgets('loading indicator while list request is pending', (
    tester,
  ) async {
    final repository = FakeTrainerRepository()..delayLists = true;
    await pumpTrainers(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pendingLists.single.complete(
      TrainersPage(
        [],
        Pagination.fromJson({'page': 1, 'limit': 20, 'total': 0}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No trainers yet. Add your first trainer.'),
      findsOneWidget,
    );
  });
  testWidgets('safe error retry and pull refresh', (tester) async {
    final repository = FakeTrainerRepository()
      ..failure = const TrainerFailure('Connection unavailable');
    await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Connection unavailable'), findsOneWidget);
    repository.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 2);
    await tester.drag(find.text('Trainers').first, const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 3);
    await tester.tap(find.byTooltip('Refresh trainers'));
    await tester.pumpAndSettle();
    expect(repository.listCalls.length, 4);
  });
  testWidgets('search and status interaction send server filters', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Pat ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.search, 'Pat');
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inactive').last);
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.query.status, TrainerStatus.inactive);
    expect(repository.listCalls.last.query.page, 1);
  });

  testWidgets('trainer details use real profile fields and back navigation', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    repository.profile.addAll({
      'branchId': '000000000000000000000099',
      'specializations': ['Strength', 'Mobility'],
      'dateOfBirth': '1995-06-12',
      'gender': 'other',
    });
    final container = await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pat Lee'));
    await tester.pumpAndSettle();
    expect(find.text('Trainer details'), findsOneWidget);
    expect(find.text('Date of birth: Jun 12, 1995'), findsOneWidget);
    expect(find.text('Strength, Mobility'), findsOneWidget);
    await reveal(tester, find.text('Record details'));
    await tester.tap(find.text('Record details'));
    await tester.pumpAndSettle();
    expect(find.text('Branch ID: 000000000000000000000099'), findsNothing);
    expect(repository.operations.single, 'get:$gymA:$trainerId');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).state.uri.path,
      AppRoutes.trainers,
    );
  });
  testWidgets(
    'creation validates, omits branch/linkage, blocks duplicate and refetches',
    (tester) async {
      final repository = FakeTrainerRepository();
      await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await openForm(tester);
      await reveal(tester, find.text('Create trainer'));
      await tester.tap(find.text('Create trainer'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–80 characters.'), findsNWidgets(2));
      expect(repository.writes, isEmpty);
      await fillRequired(tester);
      repository.saveGate = Completer<TrainerProfile>();
      await reveal(tester, find.text('Create trainer'));
      await tester.tap(find.text('Create trainer'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(repository.writes.length, 1);
      expect(repository.writes.single.keys, isNot(contains('branchId')));
      expect(repository.writes.single['status'], 'active');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      repository.saveGate!.complete(TrainerProfile.fromJson(trainerJson()));
      await tester.pumpAndSettle();
      expect(find.text('Trainer created.'), findsOneWidget);
      expect(repository.listCalls.length, 2);
      expect(find.text('Add trainer'), findsOneWidget);
    },
  );
  testWidgets(
    'edit loads server profile and prevents immutable identity changes',
    (tester) async {
      final repository = FakeTrainerRepository();
      await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pat Lee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit trainer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Trainer code: TR01 (cannot be changed)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trainerCode')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Updated',
      );
      await reveal(tester, find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repository.writes.single['firstName'], 'Updated');
      expect(repository.writes.single.keys, isNot(contains('trainerCode')));
      expect(find.text('Trainer updated.'), findsOneWidget);
      expect(find.text('Trainer details'), findsOneWidget);
    },
  );
  testWidgets(
    'editing clears nullable profile fields and preserves branch assignment',
    (tester) async {
      final repository = FakeTrainerRepository();
      repository.profile.addAll({
        'branchId': '000000000000000000000099',
        'dateOfBirth': '1995-06-12',
        'address': {'line1': 'Road', 'city': 'City', 'countryCode': 'IN'},
        'specializations': ['Strength'],
      });
      await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pat Lee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit trainer'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('dateOfBirth')));
      await tester.enterText(find.byKey(const ValueKey('dateOfBirth')), '');
      await reveal(tester, find.text('Include address'));
      await tester.tap(find.text('Include address'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('specializations')));
      await tester.enterText(find.byKey(const ValueKey('specializations')), '');
      await reveal(tester, find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repository.writes.single['dateOfBirth'], isNull);
      expect(repository.writes.single['address'], isNull);
      expect(repository.writes.single['specializations'], isNull);
      expect(repository.writes.single.containsKey('branchId'), isFalse);
      await reveal(tester, find.text('Record details'));
      await tester.tap(find.text('Record details'));
      await tester.pumpAndSettle();
      expect(find.text('Branch ID: 000000000000000000000099'), findsNothing);
      expect(find.text('No specializations provided.'), findsOneWidget);
      expect(find.text('Date of birth: 1995-06-12'), findsNothing);
    },
  );
  testWidgets('server duplicate validation remains in form for correction', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    await openForm(tester);
    await fillRequired(tester);
    repository.failure = const TrainerFailure(
      'That trainer code already exists in this gym. Choose another code.',
    );
    await reveal(tester, find.text('Create trainer'));
    await tester.tap(find.text('Create trainer'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('That trainer code already exists'),
      findsOneWidget,
    );
    expect(find.text('Create trainer'), findsOneWidget);
  });
  testWidgets('specializations validation blocks duplicate lists', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    await openForm(tester);
    await fillRequired(tester);
    await reveal(tester, find.byKey(const ValueKey('specializations')));
    await tester.enterText(
      find.byKey(const ValueKey('specializations')),
      'Yoga\nyoga',
    );
    await reveal(tester, find.text('Create trainer'));
    await tester.tap(find.text('Create trainer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use up to 10 distinct'), findsOneWidget);
    expect(repository.writes, isEmpty);
  });
  testWidgets(
    'ambiguous create failure instructs checking server list before retry',
    (tester) async {
      final repository = FakeTrainerRepository();
      await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await openForm(tester);
      await fillRequired(tester);
      repository.failure = const TrainerFailure(
        'Connection lost.',
        possiblySent: true,
      );
      await reveal(tester, find.text('Create trainer'));
      await tester.tap(find.text('Create trainer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The save may have reached the server'),
        findsOneWidget,
      );
      expect(repository.writes.length, 1);
    },
  );
  testWidgets(
    'changing gym while details open never fetches old trainer in new gym',
    (tester) async {
      final repository = FakeTrainerRepository();
      final container = await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pat Lee'));
      await tester.pumpAndSettle();
      container.read(adminGymProvider.notifier).selectGym(gymB);
      await tester.pumpAndSettle();
      expect(
        find.text('The gym context changed. Return to Trainers to continue.'),
        findsOneWidget,
      );
      expect(repository.operations.any((op) => op.contains(gymB)), isFalse);
    },
  );
  testWidgets('trainer trainer deep links cannot enter admin UI', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    final container = await pumpTrainers(
      tester,
      repository,
      role: AuthRole.trainer,
    );
    container
        .read(appRouterProvider)
        .go('${AppRoutes.trainers}/$trainerId?gymId=$gymA');
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(repository.listCalls, isEmpty);
    expect(repository.operations, isEmpty);
  });
  testWidgets(
    'successful refresh hides protected content and retains the trainer form',
    (tester) async {
      final repository = FakeTrainerRepository();
      final container = await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await openForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Retained',
      );
      final api = container.read(authApiServiceProvider) as FakeAuthApi;
      api.refreshGate = Completer<void>();
      final recovery = container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restoring your session…'), findsOneWidget);
      expect(find.byKey(const ValueKey('firstName')), findsNothing);
      api.refreshGate!.complete();
      await recovery;
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        '${AppRoutes.trainers}/new',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('firstName')))
            .controller!
            .text,
        'Retained',
      );
      expect(repository.listCalls.length, 1);
    },
  );
  testWidgets('failed recovery discards protected trainer pages', (
    tester,
  ) async {
    final repository = FakeTrainerRepository();
    final container = await pumpTrainers(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pat Lee'));
    await tester.pumpAndSettle();
    final api = container.read(authApiServiceProvider) as FakeAuthApi;
    api.refreshFailure = const AuthFailure(AuthFailureKind.invalidSession);
    await expectLater(
      container.read(sessionControllerProvider.notifier).refreshSession(),
      throwsA(isA<AuthFailure>()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Trainer details'), findsNothing);
    container
        .read(appRouterProvider)
        .go('${AppRoutes.trainers}/$trainerId?gymId=$gymA');
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);
  });
  testWidgets(
    'logout from trainer details returns to login and clears protected data',
    (tester) async {
      final repository = FakeTrainerRepository();
      final container = await pumpTrainers(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pat Lee'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Admin navigation'));
      await tester.pumpAndSettle();
      // The drawer lists more pages than fit the test screen.
      await tester.dragUntilVisible(
        find.widgetWithText(ListTile, 'More'),
        find.byType(Drawer),
        const Offset(0, -200),
      );
      // Bring it fully on screen: a tile at the very edge misses the tap.
      await tester.drag(find.byType(Drawer), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Logout'));
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(await container.read(trainersProvider.future), isNull);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );
  testWidgets(
    'unauthenticated trainer deep link redirects before any API call',
    (tester) async {
      final repository = FakeTrainerRepository();
      final container = await pumpTrainers(
        tester,
        repository,
        authenticated: false,
      );
      container
          .read(appRouterProvider)
          .go('${AppRoutes.trainers}/$trainerId?gymId=$gymA');
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(repository.listCalls, isEmpty);
      expect(repository.operations, isEmpty);
    },
  );
  testWidgets('trainer list fits 320px screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTrainers(tester, FakeTrainerRepository());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
