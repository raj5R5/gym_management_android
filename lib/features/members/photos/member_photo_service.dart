import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pending_onboarding.dart';
import 'member_photo_models.dart';
import 'member_photo_repository.dart';
import 'member_photo_store.dart';

abstract interface class MemberPhotoPicker {
  Future<Uint8List?> pick(ImageSource source);
  Future<Uint8List?> lost();
}

class NativeMemberPhotoPicker implements MemberPhotoPicker {
  NativeMemberPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<Uint8List?> pick(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        requestFullMetadata: false,
      );
      return image == null ? null : await image.readAsBytes();
    } on PlatformException catch (error) {
      throw MemberPhotoFailure(
        error.code.contains('denied') || error.code.contains('restricted')
            ? 'Photo access was denied. Enable camera or photos access in Settings, or choose another source.'
            : 'The camera or gallery could not open. Try again or choose another source.',
      );
    }
  }

  @override
  Future<Uint8List?> lost() async {
    if (!Platform.isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) {
      throw const MemberPhotoFailure(
        'The previous photo selection was interrupted. Please choose the photo again.',
      );
    }
    return response.files?.isNotEmpty == true
        ? await response.files!.first.readAsBytes()
        : null;
  }
}

class MemberPhotoService {
  MemberPhotoService({
    required this.store,
    required this.repository,
    required this.picker,
    required this.isCurrent,
    required this.revision,
  });
  final MemberPhotoStore store;
  final MemberPhotoRepository repository;
  final MemberPhotoPicker picker;
  final bool Function(MemberPhotoTarget) isCurrent;
  final int Function() revision;
  final Map<String, CancelToken> _requests = {};
  bool _picking = false;
  Future<void>? _recovering;
  Future<void>? _bindings;
  void _guard(MemberPhotoTarget target, int expected) {
    if (!isCurrent(target) || revision() != expected) {
      throw const MemberPhotoFailure(
        'The account or gym changed. Reopen this member before managing its photo.',
      );
    }
  }

  void cancelRequests() {
    for (final token in _requests.values) {
      token.cancel('Photo account scope changed');
    }
    _requests.clear();
  }

  Future<void> _validate(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxMemberPhotoBytes) {
      throw const MemberPhotoFailure('Choose a photo no larger than 5 MB.');
    }
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final png =
        bytes.length >= 8 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final webp =
        bytes.length >= 12 &&
        listEquals(bytes.sublist(0, 4), [82, 73, 70, 70]) &&
        listEquals(bytes.sublist(8, 12), [87, 69, 66, 80]);
    if (!jpeg && !png && !webp) {
      throw const MemberPhotoFailure('Choose a JPEG, PNG or WebP photo.');
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 20000000) {
        throw const FormatException();
      }
    } catch (_) {
      throw const MemberPhotoFailure(
        'Choose a valid JPEG, PNG or WebP photo, up to 20 megapixels.',
      );
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<void> _saveSelection(
    MemberPhotoTarget target,
    Uint8List bytes,
    int expected,
  ) async {
    await _validate(bytes);
    _guard(target, expected);
    final old = await store.read(target);
    _guard(target, expected);
    if (old?.attempted == true) {
      throw const MemberPhotoFailure(
        'Resolve the saved photo operation before replacing the selection.',
      );
    }
    final name = await store.saveImage(bytes);
    _guard(target, expected);
    final saved = PendingMemberPhoto(
      target: target,
      operationKey: newPhotoOperationKey(),
      remove: false,
      fileName: name,
      registrationKeys: old?.registrationKeys ?? const [],
    );
    await store.write(saved);
    if (old != null) await _deletePreview(old);
  }

  Future<void> _deletePreview(PendingMemberPhoto photo) async {
    try {
      await store.deleteImage(photo);
    } catch (_) {
      debugPrint('Member photo preview cleanup could not complete.');
    }
  }

  Future<void> recoverPicker() => _recovering ??= () async {
    try {
      final target = await store.picker();
      if (target == null || !isCurrent(target)) return;
      final expected = revision();
      final bytes = await picker.lost();
      _guard(target, expected);
      if (bytes != null) await _saveSelection(target, bytes, expected);
      await store.setPicker(null);
    } finally {
      _recovering = null;
    }
  }();
  Future<PendingMemberPhoto?> pending(MemberPhotoTarget target) async {
    final expected = revision();
    _guard(target, expected);
    await recoverPicker();
    _guard(target, expected);
    final saved = await store.read(target);
    _guard(target, expected);
    return saved;
  }

  Future<PendingMemberPhoto?> select(
    MemberPhotoTarget target,
    ImageSource source,
  ) async {
    if (_picking || _requests.containsKey(target.key)) {
      throw const MemberPhotoFailure('Finish the current photo action first.');
    }
    _picking = true;
    try {
      final expected = revision();
      _guard(target, expected);
      await recoverPicker();
      final old = await store.read(target);
      _guard(target, expected);
      if (old?.attempted == true) {
        throw const MemberPhotoFailure(
          'Retry the saved photo operation before choosing another photo.',
        );
      }
      await store.setPicker(target);
      _guard(target, expected);
      final bytes = await picker.pick(source);
      _guard(target, expected);
      if (bytes != null) await _saveSelection(target, bytes, expected);
      await store.setPicker(null);
      return store.read(target);
    } finally {
      _picking = false;
      if (await store.picker() == target) await store.setPicker(null);
    }
  }

  Future<PendingMemberPhoto> stageRemoval(MemberPhotoTarget target) async {
    final expected = revision();
    _guard(target, expected);
    final old = await store.read(target);
    _guard(target, expected);
    if (old?.attempted == true) {
      throw const MemberPhotoFailure(
        'Resolve the saved photo operation before removing the photo.',
      );
    }
    final saved = PendingMemberPhoto(
      target: target,
      operationKey: newPhotoOperationKey(),
      remove: true,
    );
    await store.write(saved);
    if (old != null) await _deletePreview(old);
    return saved;
  }

  Future<void> discard(
    MemberPhotoTarget target, {
    bool knownNotCommitted = false,
  }) async {
    final expected = revision();
    _guard(target, expected);
    final old = await store.read(target);
    _guard(target, expected);
    if (old?.attempted == true && !knownNotCommitted) {
      throw const MemberPhotoFailure(
        'Retry the saved operation to verify its outcome before cancelling.',
      );
    }
    await store.forget(target);
    if (old != null) await _deletePreview(old);
  }

  Future<MemberPhotoReceipt?> apply(
    MemberPhotoTarget target,
    void Function(double) progress,
  ) async {
    final expected = revision();
    _guard(target, expected);
    if (target.memberId == null) {
      throw const MemberPhotoFailure(
        'The member must be confirmed before uploading a photo.',
      );
    }
    if (_requests.containsKey(target.key)) {
      throw const MemberPhotoFailure('This photo is already being processed.');
    }
    final cancel = CancelToken();
    _requests[target.key] = cancel;
    try {
      var pending = await store.read(target);
      _guard(target, expected);
      if (pending == null) return null;
      MemberPhotoReceipt? receipt;
      if (pending.attempted) {
        final status = await repository.status(
          target,
          pending.operationKey,
          cancel,
        );
        _guard(target, expected);
        if (status.state == 'committed') receipt = status;
        if (status.state == 'abandoned') {
          throw const MemberPhotoFailure(
            'This photo operation expired without changing the member. Cancel this selection, then choose a photo again.',
            code: 'PHOTO_CHANGED',
          );
        }
      }
      if (receipt == null) {
        final bytes = pending.remove ? null : await store.image(pending);
        _guard(target, expected);
        pending = pending.copyWith(attempted: true);
        await store.write(pending);
        _guard(target, expected);
        if (pending.remove) {
          _guard(target, expected);
          receipt = await repository.remove(
            target,
            pending.operationKey,
            cancel,
          );
        } else {
          _guard(target, expected);
          receipt = await repository.upload(
            target,
            pending,
            bytes!,
            progress,
            cancel,
          );
        }
        _guard(target, expected);
      }
      final latest = await store.read(target);
      _guard(target, expected);
      if (latest?.operationKey != pending.operationKey) {
        throw const MemberPhotoFailure(
          'The saved photo selection changed. Reopen this member.',
        );
      }
      await store.forget(target);
      await _deletePreview(pending);
      return receipt;
    } finally {
      if (identical(_requests[target.key], cancel)) {
        _requests.remove(target.key);
      }
    }
  }

  Future<void> bindRegistration(OnboardingScope scope, String key) async {
    final target = MemberPhotoTarget(scope);
    final expected = revision();
    _guard(target, expected);
    final saved = await store.read(target);
    _guard(target, expected);
    if (saved == null || saved.registrationKeys.contains(key)) return;
    await store.write(
      saved.copyWith(registrationKeys: [...saved.registrationKeys, key]),
    );
  }

  Future<void> bindConfirmed(
    OnboardingScope scope,
    String key,
    String memberId,
  ) {
    Future<void> bind() async {
      final draft = MemberPhotoTarget(scope);
      final expected = revision();
      _guard(draft, expected);
      final saved = await store.read(draft);
      _guard(draft, expected);
      if (saved == null || !saved.registrationKeys.contains(key)) return;
      final member = MemberPhotoTarget(scope, memberId: memberId);
      final existing = await store.read(member);
      _guard(member, expected);
      if (existing != null && existing.operationKey != saved.operationKey) {
        throw const MemberPhotoFailure(
          'This member already has another saved photo selection. Finish it before attaching the registration photo.',
        );
      }
      await store.write(saved.copyWith(target: member));
      await store.forget(draft);
    }

    final previous = _bindings;
    final result = previous == null ? bind() : previous.then((_) => bind());
    _bindings = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
