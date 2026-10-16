import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_repository.dart';
import 'package:gym_management_app/features/members/photos/member_photo_service.dart';

final photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1cAAAAASUVORK5CYII=',
);
final photoScope = OnboardingScope(
  environment: AppEnvironment.development,
  apiBaseUrl: 'https://example.invalid/api/v1/',
  userId: 'owner',
  gymId: 'a' * 24,
);
final photoTarget = MemberPhotoTarget(photoScope, memberId: 'b' * 24);

class PhotoPickerFake implements MemberPhotoPicker {
  Uint8List? bytes = photoBytes;
  Object? failure;
  Completer<Uint8List?>? gate;
  final sources = <ImageSource>[];
  int lostCalls = 0;
  @override
  Future<Uint8List?> pick(ImageSource source) async {
    sources.add(source);
    if (failure != null) throw failure!;
    return gate == null ? bytes : gate!.future;
  }

  @override
  Future<Uint8List?> lost() async {
    lostCalls++;
    return bytes;
  }
}

class PhotoRepositoryFake implements MemberPhotoRepository {
  final keys = <String>[];
  int reads = 0, statusCalls = 0, removals = 0;
  bool brokenImage = false;
  bool failAfterCommit = false;
  bool failBeforeCommit = false;
  bool committed = false;
  Completer<void>? gate;
  CancelToken? lastCancel;
  MemberPhotoReceipt receipt(MemberPhotoTarget target, {String? state}) =>
      MemberPhotoReceipt.fromJson({
        'memberId': target.memberId,
        'photoRevision': 1,
        'state': state,
        if (removals == 0)
          'photoUrl':
              'gyms/${target.scope.gymId}/members/${target.memberId}/photo?v=1',
      });
  @override
  Future<MemberPhotoReceipt> upload(
    MemberPhotoTarget target,
    PendingMemberPhoto pending,
    Uint8List bytes,
    void Function(double) progress,
    CancelToken cancel,
  ) async {
    keys.add(pending.operationKey);
    lastCancel = cancel;
    progress(.5);
    if (gate != null) await gate!.future;
    if (failBeforeCommit) {
      throw const MemberPhotoFailure('Storage unavailable.');
    }
    committed = true;
    if (failAfterCommit) throw const MemberPhotoFailure('Response lost.');
    return receipt(target);
  }

  @override
  Future<MemberPhotoReceipt> remove(
    MemberPhotoTarget target,
    String key,
    CancelToken cancel,
  ) async {
    keys.add(key);
    removals++;
    committed = true;
    return receipt(target);
  }

  @override
  Future<MemberPhotoReceipt> status(
    MemberPhotoTarget target,
    String key,
    CancelToken cancel,
  ) async {
    statusCalls++;
    return receipt(target, state: committed ? 'committed' : 'prepared');
  }

  @override
  Future<Uint8List> image(
    MemberPhotoTarget target,
    String url,
    CancelToken cancel,
  ) async {
    reads++;
    return brokenImage ? Uint8List.fromList([1, 2, 3]) : photoBytes;
  }
}
