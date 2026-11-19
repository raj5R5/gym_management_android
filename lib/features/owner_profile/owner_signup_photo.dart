import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../members/photos/member_photo_models.dart';
import '../members/photos/member_photo_providers.dart';
import '../members/models/pending_onboarding.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../members/photos/member_photo_service.dart';
import 'owner_profile.dart';

/// Only a local optional selection. A successful registration receipt and a
/// matching authenticated identity are both required before handoff. No password
/// or token is stored here; the normal manual sign-in flow is unchanged.
class OwnerSignupPhotoStore {
  OwnerSignupPhotoStore({Directory? directory, MemberPhotoPicker? picker})
    : _directory = directory,
      picker = picker ?? NativeMemberPhotoPicker();
  final Directory? _directory;
  final MemberPhotoPicker picker;
  Future<void> _handoffTail = Future.value();
  Future<Directory> _root() async {
    final support = _directory ?? await getApplicationSupportDirectory();
    return Directory(
      '${support.path}/owner_signup_photo_v1',
    ).create(recursive: true);
  }

  Future<File> _file(String key) async => File('${(await _root()).path}/$key');
  Future<Map<String, dynamic>?> _record() async {
    final file = await _file('draft.json');
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  Future<void> _write(Map<String, dynamic> record) async {
    final file = await _file('draft.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(record), flush: true);
    await temp.rename(file.path);
  }

  Future<Uint8List?> preview() async {
    if ((await _record())?['selected'] != true) return null;
    return (await _file('selection.photo')).readAsBytes();
  }

  Future<void> select(AppConfig config, ImageSource source) async {
    // Persist the picker context before launching Android's external activity.
    await clear();
    await _write({
      'environment': config.environment.name,
      'api': config.apiBaseUrl?.toString(),
      'picking': true,
    });
    final bytes = await picker.pick(source);
    if (bytes == null) {
      await clear();
      return;
    }
    await _save(bytes);
  }

  Future<void> _save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxMemberPhotoBytes) {
      throw const MemberPhotoFailure('Choose a photo no larger than 5 MB.');
    }
    final data = await _record();
    if (data == null) return;
    await (await _file('selection.photo')).writeAsBytes(bytes, flush: true);
    await _write({
      ...data,
      'selected': true,
      'picking': false,
      'operationKey': newPhotoOperationKey(),
    });
  }

  Future<void> recover() async {
    if ((await _record())?['picking'] != true) return;
    final bytes = await picker.lost();
    if (bytes != null) {
      await _save(bytes);
    } else {
      await clear();
    }
  }

  Future<bool> hasConfirmed(AppConfig config) async {
    final data = await _record();
    return data?['confirmedEmail'] is String &&
        data?['selected'] == true &&
        data?['environment'] == config.environment.name &&
        data?['api'] == config.apiBaseUrl.toString();
  }

  Future<void> confirmRegistration(String email) async {
    final data = await _record();
    if (data?['selected'] != true) return;
    await _write({...data!, 'confirmedEmail': email.trim().toLowerCase()});
  }

  Future<bool> handoff(
    AppConfig config,
    OwnerProfile profile,
    MemberPhotoService service,
    MemberPhotoTarget target,
  ) {
    // App startup and the editor may discover the same draft together. Only
    // one handoff can move its bytes into the shared durable outbox.
    final result = _handoffTail.then(
      (_) => _handoff(config, profile, service, target),
    );
    _handoffTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> _handoff(
    AppConfig config,
    OwnerProfile profile,
    MemberPhotoService service,
    MemberPhotoTarget target,
  ) async {
    final data = await _record();
    if (!target.isOwner ||
        profile.userId != target.scope.userId ||
        profile.gymId != target.scope.gymId ||
        data == null ||
        data['confirmedEmail'] != profile.email.trim().toLowerCase() ||
        data['environment'] != config.environment.name ||
        data['api'] != config.apiBaseUrl.toString() ||
        !service.isCurrent(target)) {
      return false;
    }
    final existing = await service.pending(target);
    if (existing != null && existing.operationKey != data['operationKey']) {
      throw const MemberPhotoFailure(
        'Finish the saved profile photo action before attaching your sign-up photo.',
      );
    }
    if (existing == null) {
      await service.stageBytes(
        target,
        (await preview())!,
        operationKey: data['operationKey'] as String?,
      );
    }
    // The normal photo outbox now owns the selection, including retry/recovery.
    await clear();
    return true;
  }

  Future<void> clear() async {
    for (final name in ['draft.json', 'selection.photo']) {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    }
  }
}

final ownerSignupPhotoStoreProvider = Provider<OwnerSignupPhotoStore>(
  (ref) => OwnerSignupPhotoStore(),
);

/// A selected sign-up photo is applied only to the confirmed email after normal
/// sign-in. Once staged, the shared durable outbox owns uncertain outcomes.
final ownerSignupPhotoRecoveryProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final scope = ref.watch(adminGymProvider);
  final config = ref.watch(appConfigProvider);
  if (scope == null || config.apiBaseUrl == null) return;
  final store = ref.read(ownerSignupPhotoStoreProvider);
  if (!await store.hasConfirmed(config) || !ref.mounted) return;
  final profile = await ref.read(ownerProfileProvider.future);
  if (!ref.mounted || profile == null) return;
  final target = MemberPhotoTarget.owner(
    OnboardingScope.fromConfig(
      config,
      userId: scope.userId,
      gymId: scope.gymId,
    ),
  );
  final service = ref.read(memberPhotoServiceProvider);
  final staged = await store.handoff(config, profile, service, target);
  if (staged && ref.mounted && service.isCurrent(target)) {
    ref.invalidate(memberPhotoControllerProvider(target));
    await ref.read(memberPhotoControllerProvider(target).future);
    if (ref.mounted && service.isCurrent(target)) {
      final saved = await ref
          .read(memberPhotoControllerProvider(target).notifier)
          .upload();
      if (!saved) {
        throw const MemberPhotoFailure(
          'Your optional sign-up photo is saved on this device. Open Edit owner profile to retry the upload.',
        );
      }
    }
  }
}, retry: (_, _) => null);
