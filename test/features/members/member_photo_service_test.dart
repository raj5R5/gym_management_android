import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_service.dart';
import 'package:gym_management_app/features/members/photos/member_photo_store.dart';
import 'photo_fakes.dart';

import 'photo_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryMemberPhotoStore store;
  late PhotoPickerFake picker;
  late PhotoRepositoryFake repo;
  late MemberPhotoService service;
  var current = true, revision = 1;
  MemberPhotoService create() => MemberPhotoService(
    store: store,
    repository: repo,
    picker: picker,
    isCurrent: (_) => current,
    revision: () => revision,
  );
  setUp(() {
    store = MemoryMemberPhotoStore();
    picker = PhotoPickerFake();
    repo = PhotoRepositoryFake();
    current = true;
    revision = 1;
    service = create();
  });

  test(
    'gallery/camera selection, replacement and cancel never dispatch an upload',
    () async {
      final first = await service.select(photoTarget, ImageSource.gallery);
      expect(first!.attempted, false);
      expect(store.files.length, 1);
      picker.bytes = null;
      expect(
        (await service.select(photoTarget, ImageSource.camera))!.operationKey,
        first.operationKey,
      );
      picker.bytes = photoBytes;
      final next = await service.select(photoTarget, ImageSource.camera);
      expect(next!.operationKey, isNot(first.operationKey));
      expect(store.files.length, 1);
      expect(picker.sources, [
        ImageSource.gallery,
        ImageSource.camera,
        ImageSource.camera,
      ]);
      await service.discard(photoTarget);
      expect(store.records, isEmpty);
      expect(store.files, isEmpty);
      expect(repo.keys, isEmpty);
    },
  );
  test(
    'upload reports progress and clears only the confirmed operation',
    () async {
      final pending = await service.select(photoTarget, ImageSource.gallery);
      final progress = <double>[];
      final receipt = await service.apply(photoTarget, progress.add);
      expect(receipt!.revision, 1);
      expect(progress, [.5]);
      expect(repo.keys, [pending!.operationKey]);
      expect(store.records, isEmpty);
      expect(store.files, isEmpty);
    },
  );
  test(
    'lost success is recovered after restart using status without bytes or another upload',
    () async {
      final saved = await service.select(photoTarget, ImageSource.gallery);
      repo.failAfterCommit = true;
      await expectLater(
        service.apply(photoTarget, (_) {}),
        throwsA(isA<MemberPhotoFailure>()),
      );
      expect((await store.read(photoTarget))!.attempted, true);
      store.files.clear();
      service = create();
      expect((await service.apply(photoTarget, (_) {}))!.revision, 1);
      expect(repo.keys, [saved!.operationKey]);
      expect(repo.statusCalls, 1);
      expect(store.records, isEmpty);
    },
  );
  test(
    'provider failure retains exact key and verifies status before retry',
    () async {
      final saved = await service.select(photoTarget, ImageSource.gallery);
      repo.failBeforeCommit = true;
      await expectLater(
        service.apply(photoTarget, (_) {}),
        throwsA(isA<MemberPhotoFailure>()),
      );
      await expectLater(
        service.discard(photoTarget),
        throwsA(isA<MemberPhotoFailure>()),
      );
      await expectLater(
        service.select(photoTarget, ImageSource.camera),
        throwsA(isA<MemberPhotoFailure>()),
      );
      repo.failBeforeCommit = false;
      await service.apply(photoTarget, (_) {});
      expect(repo.keys, [saved!.operationKey, saved.operationKey]);
      expect(repo.statusCalls, 1);
    },
  );
  test('missing preview before first dispatch remains cancellable', () async {
    await service.select(photoTarget, ImageSource.gallery);
    store.files.clear();
    await expectLater(
      service.apply(photoTarget, (_) {}),
      throwsA(isA<MemberPhotoFailure>()),
    );
    expect((await store.read(photoTarget))!.attempted, false);
    expect(repo.keys, isEmpty);
    await service.discard(photoTarget);
    expect(store.records, isEmpty);
  });
  test(
    'registration and correction aliases bind only after confirmation and never create a member',
    () async {
      final draft = MemberPhotoTarget(photoScope);
      final saved = await service.select(draft, ImageSource.gallery);
      await expectLater(
        service.apply(draft, (_) {}),
        throwsA(isA<MemberPhotoFailure>()),
      );
      await service.bindRegistration(photoScope, 'first-registration-key');
      await service.bindRegistration(photoScope, 'corrected-registration-key');
      await service.bindConfirmed(
        photoScope,
        'unrelated-registration',
        photoTarget.memberId!,
      );
      expect(await store.read(draft), isNotNull);
      expect(await store.read(photoTarget), isNull);
      await service.bindConfirmed(
        photoScope,
        'corrected-registration-key',
        photoTarget.memberId!,
      );
      await service.bindConfirmed(
        photoScope,
        'first-registration-key',
        photoTarget.memberId!,
      );
      expect(await store.read(draft), isNull);
      expect(
        (await store.read(photoTarget))!.operationKey,
        saved!.operationKey,
      );
      expect(repo.keys, isEmpty);
      await service.apply(photoTarget, (_) {});
      expect(repo.keys, [saved.operationKey]);
    },
  );
  test(
    'removal uses its own durable operation and clears confirmed record',
    () async {
      final pending = await service.stageRemoval(photoTarget);
      expect(pending.remove, true);
      final receipt = await service.apply(photoTarget, (_) {});
      expect(receipt!.url, isNull);
      expect(repo.removals, 1);
      expect(repo.keys, [pending.operationKey]);
      expect(store.records, isEmpty);
    },
  );
  test(
    'logout during upload cancels request and retains result for original account recovery',
    () async {
      await service.select(photoTarget, ImageSource.gallery);
      repo.gate = Completer<void>();
      final job = service.apply(photoTarget, (_) {});
      final assertion = expectLater(job, throwsA(isA<MemberPhotoFailure>()));
      while (repo.lastCancel == null) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      revision++;
      service.cancelRequests();
      expect(repo.lastCancel!.isCancelled, true);
      repo.gate!.complete();
      await assertion;
      expect((await store.read(photoTarget))!.attempted, true);
      current = true;
      service = create();
      await service.apply(photoTarget, (_) {});
      expect(repo.keys.length, 1);
    },
  );
  test(
    'scope change while picker is open cannot attach selection to another account',
    () async {
      picker.gate = Completer<Uint8List?>();
      final pick = service.select(photoTarget, ImageSource.gallery);
      final assertion = expectLater(pick, throwsA(isA<MemberPhotoFailure>()));
      while (picker.sources.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      revision++;
      picker.gate!.complete(photoBytes);
      await assertion;
      expect(store.records, isEmpty);
      expect(store.activePicker, isNull);
    },
  );
  test(
    'permission error is recoverable and does not discard prior preview',
    () async {
      final saved = await service.select(photoTarget, ImageSource.gallery);
      picker.failure = const MemberPhotoFailure('Camera access denied.');
      await expectLater(
        service.select(photoTarget, ImageSource.camera),
        throwsA(isA<MemberPhotoFailure>()),
      );
      expect(
        (await store.read(photoTarget))!.operationKey,
        saved!.operationKey,
      );
      expect(store.activePicker, isNull);
    },
  );
  test(
    'Android lost picker data recovers once and only within its stored account scope',
    () async {
      await store.setPicker(photoTarget);
      current = false;
      await service.recoverPicker();
      expect(picker.lostCalls, 0);
      current = true;
      await service.recoverPicker();
      await service.recoverPicker();
      expect(picker.lostCalls, 1);
      expect(await store.read(photoTarget), isNotNull);
      expect(repo.keys, isEmpty);
    },
  );
  test(
    'oversize, unsupported and truncated images never enter the outbox',
    () async {
      for (final bytes in [
        Uint8List(maxMemberPhotoBytes + 1),
        Uint8List.fromList([71, 73, 70, 56]),
        Uint8List.fromList([255, 216, 255]),
      ]) {
        picker.bytes = bytes;
        await expectLater(
          service.select(photoTarget, ImageSource.gallery),
          throwsA(isA<MemberPhotoFailure>()),
        );
        expect(store.records, isEmpty);
        expect(repo.keys, isEmpty);
      }
    },
  );
  test('failed local metadata write prevents network dispatch', () async {
    await service.select(photoTarget, ImageSource.gallery);
    store.failWrite = true;
    await expectLater(
      service.apply(photoTarget, (_) {}),
      throwsA(isA<MemberPhotoFailure>()),
    );
    expect(repo.keys, isEmpty);
    expect((await store.read(photoTarget))!.attempted, false);
  });
  test(
    'private file storage survives recreation, isolates scopes and preserves corrupt metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'member-photo-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      var disk = FileMemberPhotoStore(directory: directory);
      final name = await disk.saveImage(photoBytes);
      final pending = PendingMemberPhoto(
        target: photoTarget,
        operationKey: newPhotoOperationKey(),
        remove: false,
        fileName: name,
      );
      await disk.write(pending);
      await disk.setPicker(photoTarget);
      disk = FileMemberPhotoStore(directory: directory);
      expect(
        (await disk.read(photoTarget))!.operationKey,
        pending.operationKey,
      );
      expect(await disk.image(pending), photoBytes);
      expect(await disk.picker(), photoTarget);
      final other = MemberPhotoTarget(
        OnboardingScope(
          environment: photoScope.environment,
          apiBaseUrl: photoScope.apiBaseUrl,
          userId: 'other-owner',
          gymId: photoScope.gymId,
        ),
        memberId: photoTarget.memberId,
      );
      expect(await disk.read(other), isNull);
      final metadata = await directory
          .list(recursive: true)
          .where((file) => file.path.endsWith('operation.json'))
          .cast<File>()
          .single;
      await metadata.writeAsString('{broken');
      await expectLater(
        disk.read(photoTarget),
        throwsA(isA<MemberPhotoFailure>()),
      );
      expect(await metadata.readAsString(), '{broken');
      await disk.forget(photoTarget);
      await disk.deleteImage(pending);
      await disk.setPicker(null);
      expect(await disk.read(photoTarget), isNull);
      expect(await disk.picker(), isNull);
    },
  );
}
