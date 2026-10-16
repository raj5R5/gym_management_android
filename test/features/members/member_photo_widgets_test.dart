import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import 'package:gym_management_app/features/members/photos/member_photo_service.dart';
import 'package:gym_management_app/features/members/photos/member_photo_widgets.dart';
import 'package:gym_management_app/features/members/presentation/member_form_page.dart';
import 'package:gym_management_app/features/members/presentation/member_details_cards.dart';
import 'package:gym_management_app/features/members/presentation/member_list_widgets.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'member_fakes.dart';
import 'photo_fakes.dart';
import 'photo_test_support.dart';

class PhotoGym extends AdminGymController {
  void leave() => state = null;
  @override
  AdminGymContext? build() =>
      (userId: photoScope.userId, gymId: photoScope.gymId);
}

class DeniedPicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(maxWidth, 1600);
    expect(maxHeight, 1600);
    expect(imageQuality, 82);
    expect(requestFullMetadata, false);
    throw PlatformException(
      code: 'camera_access_denied',
      message: 'private platform detail',
    );
  }
}

void main() {
  setUpAll(() async {
    // Measure compact layouts with the same bundled fonts used on the phone.
    for (final family in ['Inter', 'SpaceGrotesk']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  late MemoryMemberPhotoStore store;
  late PhotoPickerFake picker;
  late PhotoRepositoryFake repo;
  late MemberPhotoService service;
  late ProviderContainer container;
  var closed = false;
  void close() {
    if (!closed) {
      closed = true;
      container.dispose();
    }
  }

  MemberProfile member({bool photo = false}) => MemberProfile.fromJson({
    ...profileJson(),
    'id': photoTarget.memberId,
    if (photo)
      'photoUrl':
          'gyms/${photoScope.gymId}/members/${photoTarget.memberId}/photo?v=1',
    if (photo) 'photoRevision': 1,
  });
  setUp(() async {
    closed = false;
    store = MemoryMemberPhotoStore();
    picker = PhotoPickerFake();
    repo = PhotoRepositoryFake();
    service = MemberPhotoService(
      store: store,
      repository: repo,
      picker: picker,
      isCurrent: (_) => true,
      revision: () => 1,
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromValues(apiBaseUrl: photoScope.apiBaseUrl),
        ),
        adminGymProvider.overrideWith(PhotoGym.new),
        memberPhotoServiceProvider.overrideWithValue(service),
        memberPhotoRepositoryProvider.overrideWithValue(repo),
        memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
      ],
    );
    // Complete fixture initialization before entering the widget fake clock.
    await Future<void>.value();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(360, 812),
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  test(
    'native picker requests bounded compression and maps denied permission safely',
    () async {
      await expectLater(
        NativeMemberPhotoPicker(
          picker: DeniedPicker(),
        ).pick(ImageSource.camera),
        throwsA(
          isA<MemberPhotoFailure>().having(
            (e) => e.message,
            'safe permissions guidance',
            contains('Settings'),
          ),
        ),
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'compact portrait keeps size with no image, loaded image and broken image, dark=$dark',
      (tester) async {
        await mount(
          tester,
          Column(
            children: [
              MemberPortrait(member: member(), compact: true),
              MemberPortrait(member: member(photo: true)),
              MemberPhotoAvatar(member: member(photo: true)),
            ],
          ),
          dark: dark,
        );
        expect(tester.getSize(find.byType(MemberPortrait).first).height, 72);
        expect(tester.getSize(find.byType(MemberPortrait).last).height, 100);
        expect(
          repo.reads,
          1,
          reason:
              'Cards and details share the same authenticated image provider.',
        );
        expect(find.byType(Image), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        // A fresh revision with invalid image bytes falls back to initials in the
        // same bounds; decode errors must not escape or alter the compact layout.
        container.invalidate(memberPhotoImageProvider);
        repo.brokenImage = true;
        await tester.pumpAndSettle();
        expect(find.text('AR'), findsWidgets);
        expect(tester.getSize(find.byType(MemberPortrait).last).height, 100);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        close();
      },
    );
    testWidgets(
      'editor previews/cancels and disables controls during progress, dark=$dark',
      (tester) async {
        await mount(
          tester,
          MemberPhotoEditor(target: photoTarget, member: member()),
          dark: dark,
          scale: 1.5,
        );
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();
        expect(find.text('Selected photo · Preview'), findsOneWidget);
        expect(repo.keys, isEmpty);
        await tester.tap(find.text('Cancel selection'));
        await tester.pumpAndSettle();
        expect(store.records, isEmpty);
        await tester.tap(find.text('Camera'));
        await tester.pumpAndSettle();
        repo.gate = Completer<void>();
        await tester.tap(find.text('Upload photo'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Uploading photo · 50%'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(
                find
                    .ancestor(
                      of: find.text('Gallery'),
                      matching: find.byWidgetPredicate(
                        (w) => w is ButtonStyleButton,
                      ),
                    )
                    .first,
              )
              .onPressed,
          isNull,
        );
        repo.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Photo saved.'), findsOneWidget);
        expect(store.records, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        close();
      },
    );
  }
  testWidgets(
    'uncertain upload offers exact retry and no replace/cancel until status resolves',
    (tester) async {
      await mount(
        tester,
        MemberPhotoEditor(target: photoTarget, member: member()),
      );
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      repo.failAfterCommit = true;
      await tester.tap(find.text('Upload photo'));
      await tester.pumpAndSettle();
      expect(find.text('Response lost.'), findsOneWidget);
      expect(find.text('Cancel selection'), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find
                  .ancestor(
                    of: find.text('Camera'),
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Retry saved photo'));
      await tester.pumpAndSettle();
      expect(repo.keys.length, 1);
      expect(repo.statusCalls, 1);
      expect(find.text('Photo saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
  testWidgets(
    'removal requires confirmation and restores the initials fallback',
    (tester) async {
      await mount(
        tester,
        MemberPhotoEditor(target: photoTarget, member: member(photo: true)),
      );
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove profile photo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
      await tester.pumpAndSettle();
      expect(repo.removals, 1);
      expect(find.text('Photo removed.'), findsOneWidget);
      expect(find.text('Initials avatar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
  testWidgets(
    'photo save preserves unsaved member form values and does not submit member edits',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        close();
      });
      // Use an actual editable form and its real profile provider; a photo refresh
      // must not replace it with a loading widget and lose the typed draft.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MemberFormPage(
                gymId: photoScope.gymId,
                memberId: photoTarget.memberId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('firstName')),
        'Unsaved draft',
      );
      await tester.runAsync(
        () => service.select(photoTarget, ImageSource.gallery),
      );
      container.invalidate(memberPhotoControllerProvider(photoTarget));
      await tester.pumpAndSettle();
      await container
          .read(memberPhotoControllerProvider(photoTarget).notifier)
          .upload();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('firstName')))
            .controller!
            .text,
        'Unsaved draft',
      );
      expect(repo.keys.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
  testWidgets(
    'confirmed registration photo failure leaves a retry without any registration resubmission',
    (tester) async {
      final draft = MemberPhotoTarget(photoScope);
      await tester.runAsync(() => service.select(draft, ImageSource.gallery));
      await service.bindRegistration(photoScope, 'confirmed-key');
      repo.failBeforeCommit = true;
      await mount(
        tester,
        RegistrationPhotoRecovery(
          scope: photoScope,
          operationKey: 'confirmed-key',
          memberId: photoTarget.memberId,
        ),
      );
      await tester.pumpAndSettle();
      // Wait for the post-frame automatic photo upload after confirmation.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(repo.keys.length, 1);
      expect(find.text('Storage unavailable.'), findsOneWidget);
      expect(find.text('Retry saved photo'), findsOneWidget);
      expect(repo.keys.length, 1);
      expect(await store.read(draft), isNull);
      expect(await store.read(photoTarget), isNotNull);
      repo.failBeforeCommit = false;
      await tester.tap(find.text('Retry saved photo'));
      await tester.pumpAndSettle();
      expect(repo.keys[0], repo.keys[1]);
      expect(repo.statusCalls, 1);
      expect(store.records, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '128dp profile photo opens a scoped viewer without another download, dark=$dark',
      (tester) async {
        await mount(
          tester,
          MemberProfileCard(
            member: member(photo: true),
            scope: (
              userId: photoScope.userId,
              gymId: photoScope.gymId,
              memberId: photoTarget.memberId!,
            ),
          ),
          dark: dark,
        );
        final thumbnail = find.byType(MemberPhotoAvatar);
        expect(tester.getSize(thumbnail), const Size(128, 128));
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
        expect(find.byType(ClipOval), findsNothing);
        expect(repo.reads, 1);
        await tester.tap(find.byTooltip('View larger photo'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Profile photo'), findsOneWidget);
        final enlarged = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Image),
        );
        expect(tester.widget<Image>(enlarged).fit, BoxFit.contain);
        expect(tester.getSize(enlarged).width, greaterThan(128));
        expect(
          repo.reads,
          1,
          reason: 'Viewer and thumbnail reuse the same scoped revision cache.',
        );
        await tester.tap(find.byTooltip('Close photo'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        close();
      },
    );
    for (final config in [(360.0, 1.0), (320.0, 1.25), (360.0, 2.0)]) {
      testWidgets(
        'photo cards reflow at width ${config.$1} scale ${config.$2}, dark=$dark',
        (tester) async {
          final json = summaryJson(populated: true);
          json['member'] = {...profileJson(), 'id': photoTarget.memberId};
          final summary = MemberSummary.fromJson(json);
          await mount(
            tester,
            ResponsiveMemberGrid(
              children: [
                MemberDirectoryCard(
                  member: member(photo: true),
                  summary: AsyncData(summary),
                  onTap: () {},
                ),
                MemberDirectoryCard(
                  member: member(),
                  summary: AsyncData(summary),
                  onTap: () {},
                ),
              ],
            ),
            dark: dark,
            size: Size(config.$1, 1000),
            scale: config.$2,
          );
          final portraits = find.byType(MemberPortrait);
          final cards = find.byType(MemberDirectoryCard);
          final oneColumn = config.$1 < 360 || config.$2 > 1.25;
          for (var index = 0; index < 2; index++) {
            final card = tester.getSize(cards.at(index));
            final photo = tester.getSize(portraits.at(index));
            expect(photo.height, 168);
            expect(photo.width, card.width);
          }
          if (!oneColumn) {
            expect(
              tester.getTopLeft(portraits.first).dy,
              tester.getTopLeft(portraits.last).dy,
            );
          }
          expect(repo.reads, 1);
          expect(find.text('AR'), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          close();
        },
      );
    }
  }
  testWidgets('viewer hides the previous member when account or gym changes', (
    tester,
  ) async {
    await mount(
      tester,
      MemberPhotoAvatar.cover(
        member: member(photo: true),
        width: 128,
        height: 128,
        borderRadius: BorderRadius.circular(12),
        viewable: true,
      ),
    );
    await tester.tap(find.byTooltip('View larger photo'));
    await tester.pumpAndSettle();
    (container.read(adminGymProvider.notifier) as PhotoGym).leave();
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Alex River')),
      findsNothing,
    );
    expect(find.textContaining('The account or gym changed.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    close();
  });
  testWidgets(
    'removal receipt replaces thumbnail and open viewer with initials',
    (tester) async {
      await mount(
        tester,
        MemberPhotoAvatar.cover(
          member: member(photo: true),
          width: 128,
          height: 128,
          borderRadius: BorderRadius.circular(12),
          viewable: true,
        ),
      );
      await tester.tap(find.byTooltip('View larger photo'));
      await tester.pumpAndSettle();
      container
          .read(memberPhotoReceiptsProvider.notifier)
          .save(
            photoTarget,
            MemberPhotoReceipt.fromJson({
              'memberId': photoTarget.memberId,
              'photoRevision': 2,
            }),
          );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('AR'), findsNWidgets(2));
      expect(repo.reads, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
  testWidgets(
    'long profile identity and viewer remain scrollable on small landscape with triple text',
    (tester) async {
      final longMember = MemberProfile.fromJson({
        ...profileJson(),
        'id': photoTarget.memberId,
        'firstName': 'Alexandria Catherine',
        'lastName': 'River Montgomery',
        'photoUrl':
            'gyms/${photoScope.gymId}/members/${photoTarget.memberId}/photo?v=1',
        'photoRevision': 1,
      });
      await mount(
        tester,
        MemberProfileCard(
          member: longMember,
          scope: (
            userId: photoScope.userId,
            gymId: photoScope.gymId,
            memberId: photoTarget.memberId!,
          ),
        ),
        size: const Size(568, 320),
        scale: 3,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('View larger photo'));
      await tester.tap(find.byTooltip('View larger photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Close photo').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      close();
    },
  );
}
