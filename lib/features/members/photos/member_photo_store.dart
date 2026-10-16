import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'member_photo_models.dart';

abstract interface class MemberPhotoStore {
  Future<PendingMemberPhoto?> read(MemberPhotoTarget target);
  Future<void> write(PendingMemberPhoto photo);
  Future<void> forget(MemberPhotoTarget target);
  Future<String> saveImage(Uint8List bytes);
  Future<Uint8List> image(PendingMemberPhoto photo);
  Future<void> deleteImage(PendingMemberPhoto photo);
  Future<MemberPhotoTarget?> picker();
  Future<void> setPicker(MemberPhotoTarget? target);
}

/// Photos and their outbox live in private Application Support, not picker
/// cache or external gallery storage. Tokens and financial records stay in
/// their existing secure stores. Writes are serialized and atomically renamed.
class FileMemberPhotoStore implements MemberPhotoStore {
  FileMemberPhotoStore({Directory? directory}) : _supportDirectory = directory;
  final Directory? _supportDirectory;
  Future<Directory>? _directory;
  Future<void> _tail = Future.value();
  Future<Directory> _root() => _directory ??= () async {
    final support = _supportDirectory ?? await getApplicationSupportDirectory();
    return Directory(
      '${support.path}/member_photo_outbox_v1',
    ).create(recursive: true);
  }();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File> _metadata(MemberPhotoTarget target) async {
    final encoded = base64UrlEncode(utf8.encode(target.key));
    // Bound individual path components even with a long development API URL.
    final segments = [
      for (var i = 0; i < encoded.length; i += 100)
        encoded.substring(i, (i + 100).clamp(0, encoded.length)),
    ];
    return File(
      '${(await _root()).path}/records/${segments.join('/')}/operation.json',
    );
  }

  Future<void> _atomic(File file, String text) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${newPhotoOperationKey()}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<PendingMemberPhoto?> read(
    MemberPhotoTarget target,
  ) => _serial(() async {
    try {
      final file = await _metadata(target);
      if (!await file.exists()) return null;
      final saved = PendingMemberPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
      );
      if (saved.target != target) throw const FormatException();
      return saved;
    } catch (_) {
      throw const MemberPhotoFailure(
        'The saved photo selection could not be read. It has not been discarded.',
      );
    }
  });
  @override
  Future<void> write(PendingMemberPhoto photo) => _serial(() async {
    try {
      await _atomic(await _metadata(photo.target), photo.encode());
    } catch (_) {
      throw const MemberPhotoFailure(
        'The photo selection could not be saved on this device. Please retry.',
      );
    }
  });
  @override
  Future<void> forget(MemberPhotoTarget target) => _serial(() async {
    final file = await _metadata(target);
    if (await file.exists()) await file.delete();
  });
  @override
  Future<String> saveImage(Uint8List bytes) => _serial(() async {
    if (bytes.isEmpty || bytes.length > maxMemberPhotoBytes) {
      throw const MemberPhotoFailure('Choose a photo no larger than 5 MB.');
    }
    final name = '${newPhotoOperationKey()}.photo';
    final file = File('${(await _root()).path}/images/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return name;
  });
  @override
  Future<Uint8List> image(PendingMemberPhoto photo) async {
    if (photo.fileName == null) {
      throw const MemberPhotoFailure('The selected photo is missing.');
    }
    try {
      final file = File('${(await _root()).path}/images/${photo.fileName}');
      if (await file.length() > maxMemberPhotoBytes) {
        throw const FormatException();
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const FormatException();
      return bytes;
    } catch (_) {
      throw const MemberPhotoFailure(
        'The saved photo file is unavailable. Your existing member photo has not been changed.',
      );
    }
  }

  @override
  Future<void> deleteImage(PendingMemberPhoto photo) => _serial(() async {
    if (photo.fileName == null) return;
    final file = File('${(await _root()).path}/images/${photo.fileName}');
    if (await file.exists()) await file.delete();
  });
  @override
  Future<MemberPhotoTarget?> picker() => _serial(() async {
    final file = File('${(await _root()).path}/picker.json');
    if (!await file.exists()) return null;
    return MemberPhotoTarget.fromJson(
      Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
    );
  });
  @override
  Future<void> setPicker(MemberPhotoTarget? target) => _serial(() async {
    final file = File('${(await _root()).path}/picker.json');
    if (target == null) {
      if (await file.exists()) await file.delete();
    } else {
      await _atomic(file, jsonEncode(target.toJson()));
    }
  });
}
