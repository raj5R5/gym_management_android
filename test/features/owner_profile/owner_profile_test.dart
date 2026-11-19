import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_repository.dart';
import 'package:gym_management_app/features/members/photos/member_photo_service.dart';
import 'package:gym_management_app/features/owner_profile/owner_profile.dart';
import 'package:gym_management_app/features/owner_profile/owner_signup_photo.dart';
import '../auth/auth_fakes.dart';
import '../members/photo_fakes.dart';
import '../members/photo_test_support.dart';

Map<String, dynamic> profileJson() => {
  'userId': photoScope.userId,
  'gymId': photoScope.gymId,
  'displayName': 'Test Owner',
  'email': 'owner@example.test',
  'phone': '',
  'gymName': 'Test Gym',
  'gymContactPhone': '',
  'gymContactEmail': '',
  'photoRevision': 0,
  'completion': {'completed': 3, 'total': 6},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = MemberPhotoTarget.owner(photoScope);
  final path = 'gyms/${photoScope.gymId}/owner-profile';
  test(
    'owner outbox identity is distinct from member/draft and round-trips without changing old keys',
    () {
      expect(target.key, isNot(photoTarget.key));
      expect(target.key, isNot(MemberPhotoTarget(photoScope).key));
      expect(MemberPhotoTarget.fromJson(target.toJson()), target);
      expect(MemberPhotoTarget.fromJson(photoTarget.toJson()).isOwner, false);
      expect(
        photoTarget.key,
        '${photoScope.storageKey}.photo.${photoTarget.memberId}',
      );
      expect(target.canUpload, true);
    },
  );
  test(
    'owner repository verifies account/gym, completion bounds and protected photo URL',
    () async {
      final client = Dio(BaseOptions(baseUrl: photoScope.apiBaseUrl));
      addTearDown(() => client.close(force: true));
      final repo = DioOwnerProfileRepository(client);
      for (final bad in [
        {...profileJson(), 'userId': 'foreign'},
        {...profileJson(), 'gymId': 'b' * 24},
        {
          ...profileJson(),
          'completion': {'completed': 7, 'total': 6},
        },
        {...profileJson(), 'photoUrl': 'https://attacker.test/photo'},
      ]) {
        client.httpClientAdapter = CallbackAdapter(
          (_) => jsonResponse({'success': true, 'data': bad}),
        );
        await expectLater(
          repo.get((
            userId: photoScope.userId,
            gymId: photoScope.gymId,
          ), CancelToken()),
          throwsA(isA<OwnerProfileFailure>()),
        );
      }
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.path, path);
        return jsonResponse({'success': true, 'data': profileJson()});
      });
      expect(
        (await repo.get((
          userId: photoScope.userId,
          gymId: photoScope.gymId,
        ), CancelToken())).completion,
        .5,
      );
    },
  );
  test(
    'shared photo repository uses the owner endpoint and rejects foreign owner/gym receipts',
    () async {
      final client = Dio(BaseOptions(baseUrl: photoScope.apiBaseUrl));
      addTearDown(() => client.close(force: true));
      final repo = DioMemberPhotoRepository(client);
      Map<String, dynamic> receipt() => {
        'success': true,
        'data': {
          'userId': photoScope.userId,
          'gymId': photoScope.gymId,
          'photoRevision': 1,
          'photoUrl': '$path/photo?v=1',
        },
      };
      client.httpClientAdapter = CallbackAdapter((request) {
        expect(request.path, '$path/photo');
        return jsonResponse(receipt());
      });
      final key = newPhotoOperationKey();
      expect(
        (await repo.remove(target, key, CancelToken())).memberId,
        photoScope.userId,
      );
      for (final field in ['userId', 'gymId']) {
        final data = receipt();
        (data['data'] as Map)[field] = 'foreign';
        client.httpClientAdapter = CallbackAdapter((_) => jsonResponse(data));
        await expectLater(
          repo.remove(target, key, CancelToken()),
          throwsA(isA<MemberPhotoFailure>()),
        );
      }
      var requests = 0;
      client.httpClientAdapter = CallbackAdapter((_) {
        requests++;
        return jsonResponse(receipt());
      });
      for (final url in [
        'https://attacker.test/photo',
        '$path/photo?v=1&x=2',
        'gyms/${photoScope.gymId}/members/${photoTarget.memberId}/photo?v=1',
      ]) {
        await expectLater(
          repo.image(target, url, CancelToken()),
          throwsA(isA<MemberPhotoFailure>()),
        );
      }
      expect(requests, 0);
    },
  );
  test(
    'sign-up photo stays local until confirmed registration AND matching environment/email/account scope',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owner-signup-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final picker = PhotoPickerFake();
      final draft = OwnerSignupPhotoStore(directory: directory, picker: picker);
      final config = AppConfig.fromValues(apiBaseUrl: photoScope.apiBaseUrl);
      final store = MemoryMemberPhotoStore();
      final service = MemberPhotoService(
        store: store,
        repository: PhotoRepositoryFake(),
        picker: picker,
        revision: () => 1,
        isCurrent: (value) => value == target,
      );
      final profile = OwnerProfile.fromJson(profileJson());
      await draft.select(config, ImageSource.gallery);
      expect(await draft.handoff(config, profile, service, target), false);
      await draft.confirmRegistration('another@example.test');
      expect(await draft.handoff(config, profile, service, target), false);
      await draft.confirmRegistration(' OWNER@example.test ');
      final wrongApi = AppConfig.fromValues(
        apiBaseUrl: 'https://other.invalid/api/v1/',
      );
      expect(await draft.handoff(wrongApi, profile, service, target), false);
      expect(store.records, isEmpty);
      expect(await draft.handoff(config, profile, service, target), true);
      final pending = await store.read(target);
      expect(pending, isNotNull);
      expect(pending!.attempted, false);
      expect(await store.image(pending), photoBytes);
      expect(await draft.preview(), isNull);
    },
  );
  test(
    'sign-up handoff preserves an existing owner outbox operation and its selection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owner-signup-conflict-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final picker = PhotoPickerFake();
      final config = AppConfig.fromValues(apiBaseUrl: photoScope.apiBaseUrl);
      final draft = OwnerSignupPhotoStore(directory: directory, picker: picker);
      final store = MemoryMemberPhotoStore();
      final repo = PhotoRepositoryFake();
      final service = MemberPhotoService(
        store: store,
        repository: repo,
        picker: picker,
        revision: () => 1,
        isCurrent: (_) => true,
      );
      await service.stageBytes(target, photoBytes);
      final existing = await store.read(target);
      await draft.select(config, ImageSource.gallery);
      await draft.confirmRegistration('owner@example.test');
      await expectLater(
        draft.handoff(
          config,
          OwnerProfile.fromJson(profileJson()),
          service,
          target,
        ),
        throwsA(isA<MemberPhotoFailure>()),
      );
      expect((await store.read(target))!.operationKey, existing!.operationKey);
      expect(await draft.preview(), photoBytes);
      expect(repo.keys, isEmpty);
    },
  );
  test(
    'simultaneous sign-up recovery hands off once and rejects a foreign profile',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owner-signup-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final picker = PhotoPickerFake();
      final draft = OwnerSignupPhotoStore(directory: directory, picker: picker);
      final config = AppConfig.fromValues(apiBaseUrl: photoScope.apiBaseUrl);
      final store = MemoryMemberPhotoStore();
      final service = MemberPhotoService(
        store: store,
        repository: PhotoRepositoryFake(),
        picker: picker,
        revision: () => 1,
        isCurrent: (_) => true,
      );
      final profile = OwnerProfile.fromJson(profileJson());
      await draft.select(config, ImageSource.gallery);
      await draft.confirmRegistration(profile.email);
      final foreign = OwnerProfile.fromJson({
        ...profileJson(),
        'userId': 'another-owner',
      });
      expect(await draft.handoff(config, foreign, service, target), false);
      expect(store.records, isEmpty);
      final results = await Future.wait([
        draft.handoff(config, profile, service, target),
        draft.handoff(config, profile, service, target),
      ]);
      expect(results, [true, false]);
      expect(store.records, hasLength(1));
      expect(store.files, hasLength(1));
      expect(await draft.preview(), isNull);
    },
  );
}
