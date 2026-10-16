import 'dart:typed_data';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_store.dart';

/// Photo filesystem I/O is isolated from existing registration/payment tests.
class MemoryMemberPhotoStore implements MemberPhotoStore {
  final Map<String, PendingMemberPhoto> records = {};
  final Map<String, Uint8List> files = {};
  MemberPhotoTarget? activePicker;
  bool failWrite = false;
  @override
  Future<PendingMemberPhoto?> read(MemberPhotoTarget target) async =>
      records[target.key];
  @override
  Future<void> write(PendingMemberPhoto photo) async {
    if (failWrite) {
      throw const MemberPhotoFailure('Photo storage write failed.');
    }
    records[photo.target.key] = photo;
  }

  @override
  Future<void> forget(MemberPhotoTarget target) async {
    records.remove(target.key);
  }

  @override
  Future<String> saveImage(Uint8List bytes) async {
    final name = '${newPhotoOperationKey()}.photo';
    files[name] = Uint8List.fromList(bytes);
    return name;
  }

  @override
  Future<Uint8List> image(PendingMemberPhoto photo) async {
    final bytes = files[photo.fileName];
    if (bytes == null) throw const MemberPhotoFailure('Saved preview missing.');
    return bytes;
  }

  @override
  Future<void> deleteImage(PendingMemberPhoto photo) async {
    files.remove(photo.fileName);
  }

  @override
  Future<MemberPhotoTarget?> picker() async => activePicker;
  @override
  Future<void> setPicker(MemberPhotoTarget? target) async {
    activePicker = target;
  }
}
