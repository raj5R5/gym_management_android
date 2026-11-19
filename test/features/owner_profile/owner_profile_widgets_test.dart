import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/navigation/form_navigation_guard.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'package:gym_management_app/features/members/photos/member_photo_service.dart';
import 'package:gym_management_app/features/owner_profile/owner_profile.dart';
import 'package:gym_management_app/features/owner_profile/owner_profile_page.dart';
import 'package:gym_management_app/features/owner_profile/owner_signup_photo.dart';
import '../members/photo_fakes.dart';
import '../members/photo_test_support.dart';
import 'owner_profile_test.dart' show profileJson;

class FixedGym extends AdminGymController {
  @override
  AdminGymContext? build() =>
      (userId: photoScope.userId, gymId: photoScope.gymId);
}

class NoSignupPhoto extends OwnerSignupPhotoStore {
  @override
  Future<void> recover() async {}
  @override
  Future<bool> hasConfirmed(AppConfig config) async => false;
  @override
  Future<bool> handoff(
    AppConfig config,
    OwnerProfile profile,
    MemberPhotoService service,
    MemberPhotoTarget target,
  ) async => false;
}

class OwnerPhotosFake extends PhotoRepositoryFake {
  @override
  MemberPhotoReceipt receipt(MemberPhotoTarget target, {String? state}) =>
      MemberPhotoReceipt.fromJson({
        'memberId': target.subjectId,
        'photoRevision': 1,
        'state': state,
        if (removals == 0)
          'photoUrl': 'gyms/${target.scope.gymId}/owner-profile/photo?v=1',
      });
}

class ProfilesFake implements OwnerProfileRepository {
  bool hasPhoto = false;
  int writes = 0;
  Map<String, String>? input;
  OwnerProfileFailure? failure;
  @override
  Future<OwnerProfile> get(AdminGymContext scope, CancelToken cancel) async =>
      OwnerProfile.fromJson({
        ...profileJson(),
        'userId': scope.userId,
        'gymId': scope.gymId,
        if (hasPhoto) ...{
          'photoRevision': 1,
          'photoUrl': 'gyms/${photoScope.gymId}/owner-profile/photo?v=1',
        },
      });
  @override
  Future<OwnerProfile> save(
    AdminGymContext scope,
    Map<String, String> input,
    CancelToken cancel,
  ) async {
    writes++;
    this.input = input;
    if (failure != null) throw failure!;
    return OwnerProfile.fromJson({...profileJson(), ...input});
  }
}

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ProfilesFake profiles, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
  }) async {
    final store = MemoryMemberPhotoStore();
    final picker = PhotoPickerFake();
    final photos = OwnerPhotosFake();
    final scope = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: photoScope.apiBaseUrl),
        ),
        adminGymProvider.overrideWith(FixedGym.new),
        ownerProfileRepositoryProvider.overrideWithValue(profiles),
        ownerSignupPhotoStoreProvider.overrideWithValue(NoSignupPhoto()),
        memberPhotoRepositoryProvider.overrideWithValue(photos),
        memberPhotoServiceProvider.overrideWithValue(
          MemberPhotoService(
            store: store,
            repository: photos,
            picker: picker,
            revision: () => 1,
            isCurrent: (_) => true,
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: SafeArea(child: OwnerProfilePage())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scope;
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'owner form remains readable at 320dp and 2x text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pump(tester, ProfilesFake(), brightness: brightness, scale: 2);
        expect(find.text('OWNER PROFILE'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('profile-gymContactEmail')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pump();
        await tester.ensureVisible(find.text('Save profile'));
        await tester.pumpAndSettle();
        expect(find.text('Save profile').hitTestable(), findsOneWidget);
      },
    );
  }
  testWidgets(
    'saving details requires valid inputs and current password for a changed email',
    (tester) async {
      final profiles = ProfilesFake();
      await pump(tester, profiles);
      await tester.enterText(
        find.byKey(const ValueKey('profile-email')),
        'new@example.test',
      );
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(profiles.writes, 0);
      expect(
        find.text('Enter your current password to change the email.'),
        findsOneWidget,
      );
      final password = find.widgetWithText(TextFormField, 'Current password');
      await tester.enterText(password, 'Synthetic verification only');
      await tester.pump();
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(profiles.writes, 1);
      expect(profiles.input!['email'], 'new@example.test');
      expect(profiles.input!.keys, isNot(contains('passwordHash')));
      expect(find.textContaining('Profile saved for'), findsOneWidget);
    },
  );
  testWidgets(
    'failed save retains unsaved edits and the existing exit safeguard',
    (tester) async {
      final profiles = ProfilesFake()
        ..failure = const OwnerProfileFailure('Connection unavailable. Retry.');
      final scope = await pump(tester, profiles);
      await tester.enterText(
        find.byKey(const ValueKey('profile-displayName')),
        'Unsaved Owner',
      );
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable. Retry.'), findsOneWidget);
      expect(find.text('Unsaved Owner'), findsOneWidget);
      final decision = scope.read(formNavigationGuardProvider).allowExit();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(await decision, false);
    },
  );
  testWidgets(
    'confirmed removal replaces an old owner photo with fallback immediately',
    (tester) async {
      await pump(tester, ProfilesFake()..hasPhoto = true);
      expect(find.text('Current profile photo'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove photo'));
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
      await tester.pumpAndSettle();
      expect(find.text('Photo removed.'), findsOneWidget);
      expect(find.text('Current profile photo'), findsNothing);
      expect(find.text('Initials avatar'), findsOneWidget);
      // The removed image's bounded idle cache expires after two minutes.
      await tester.pump(const Duration(minutes: 2));
    },
  );
}
