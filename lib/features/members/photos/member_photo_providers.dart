import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/app_config.dart';
import '../../admin_dashboard/providers/dashboard_providers.dart';
import '../../auth/models/session_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/providers/session_controller.dart';
import '../../memberships/providers/payment_providers.dart';
import '../models/pending_onboarding.dart';
import '../providers/member_providers.dart';
import 'member_photo_models.dart';
import 'member_photo_repository.dart';
import 'member_photo_service.dart';
import 'member_photo_store.dart';

final memberPhotoStoreProvider = Provider<MemberPhotoStore>(
  (ref) => FileMemberPhotoStore(),
);
final memberPhotoPickerProvider = Provider<MemberPhotoPicker>(
  (ref) => NativeMemberPhotoPicker(),
);
final memberPhotoRepositoryProvider = Provider<MemberPhotoRepository>(
  (ref) => DioMemberPhotoRepository(ref.watch(authenticatedApiClientProvider)),
);
final memberPhotoServiceProvider = Provider<MemberPhotoService>((ref) {
  final config = ref.watch(appConfigProvider);
  final auth = ref.watch(authRepositoryProvider);
  final service = MemberPhotoService(
    store: ref.watch(memberPhotoStoreProvider),
    repository: ref.watch(memberPhotoRepositoryProvider),
    picker: ref.watch(memberPhotoPickerProvider),
    revision: () => auth.revision,
    isCurrent: (target) {
      if (!ref.mounted ||
          !identical(ref.read(authRepositoryProvider), auth) ||
          !identical(ref.read(appConfigProvider), config) ||
          config.apiBaseUrl == null) {
        return false;
      }
      final gym = ref.read(adminGymProvider);
      final session = ref.read(sessionControllerProvider);
      final active =
          session is SessionAuthenticated ||
          session is SessionLoading &&
              session.operation == SessionOperation.refreshing;
      return active &&
          gym != null &&
          target.scope.matches(
            OnboardingScope.fromConfig(
              config,
              userId: gym.userId,
              gymId: gym.gymId,
            ),
          );
    },
  );
  var revision = auth.revision;
  final subscription = auth.changes.listen((_) {
    if (revision != auth.revision) {
      revision = auth.revision;
      service.cancelRequests();
    }
  });
  ref.listen(adminGymProvider, (_, _) => service.cancelRequests());
  ref.onDispose(() {
    service.cancelRequests();
    subscription.cancel();
  });
  return service;
});

MemberPhotoTarget? memberPhotoTarget(WidgetRef ref, {String? memberId}) {
  final gym = ref.watch(adminGymProvider);
  final config = ref.watch(appConfigProvider);
  if (gym == null || config.apiBaseUrl == null) return null;
  return MemberPhotoTarget(
    OnboardingScope.fromConfig(config, userId: gym.userId, gymId: gym.gymId),
    memberId: memberId,
  );
}

typedef MemberPhotoImageRequest = ({MemberPhotoTarget target, String url});
final memberPhotoImageProvider = FutureProvider.autoDispose
    .family<Uint8List, MemberPhotoImageRequest>((ref, request) async {
      ref.watch(adminGymProvider);
      final service = ref.watch(memberPhotoServiceProvider);
      final expected = service.revision();
      if (!service.isCurrent(request.target)) {
        throw const MemberPhotoFailure('The photo scope changed.');
      }
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      final bytes = await ref
          .watch(memberPhotoRepositoryProvider)
          .image(request.target, request.url, cancel);
      if (!ref.mounted ||
          expected != service.revision() ||
          !service.isCurrent(request.target)) {
        throw const MemberPhotoFailure('The photo scope changed.');
      }
      // Share one authenticated download among cards/details, with a bounded idle
      // lifetime. An updated URL/revision obtains a fresh image without cache busts.
      final link = ref.keepAlive();
      Timer? timer;
      var disposed = false;
      ref.onCancel(() {
        timer?.cancel();
        if (!disposed) timer = Timer(const Duration(minutes: 2), link.close);
      });
      ref.onResume(() => timer?.cancel());
      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
      });
      return bytes;
    }, retry: (_, _) => null);

class MemberPhotoEditState {
  const MemberPhotoEditState({
    this.pending,
    this.preview,
    this.busy = false,
    this.progress,
    this.error,
    this.success,
  });
  final PendingMemberPhoto? pending;
  final Uint8List? preview;
  final bool busy;
  final double? progress;
  final MemberPhotoFailure? error;
  final String? success;
  MemberPhotoEditState working({double? progress}) => MemberPhotoEditState(
    pending: pending,
    preview: preview,
    busy: true,
    progress: progress,
  );
}

class MemberPhotoController extends AsyncNotifier<MemberPhotoEditState> {
  MemberPhotoController(this.target);
  final MemberPhotoTarget target;
  bool _busy = false;
  bool _current(MemberPhotoService service) =>
      ref.mounted &&
      service.isCurrent(target) &&
      identical(ref.read(memberPhotoServiceProvider), service);
  @override
  Future<MemberPhotoEditState> build() async {
    ref.watch(adminGymProvider);
    // Resolve dependent transports after the widget build. Configuration
    // changes may invalidate their listeners while a fresh wizard is mounting.
    await Future<void>.value();
    if (!ref.mounted) return const MemberPhotoEditState();
    final service = ref.watch(memberPhotoServiceProvider);
    if (!service.isCurrent(target)) return const MemberPhotoEditState();
    return _read(service);
  }

  Future<MemberPhotoEditState> _read(
    MemberPhotoService service, {
    MemberPhotoFailure? error,
    String? success,
  }) async {
    final pending = await service.pending(target);
    Uint8List? preview;
    if (pending != null && !pending.remove) {
      try {
        preview = await service.store.image(pending);
      } on MemberPhotoFailure catch (failure) {
        error ??= failure;
      }
    }
    return MemberPhotoEditState(
      pending: pending,
      preview: preview,
      error: error,
      success: success,
    );
  }

  Future<bool> _run(
    Future<void> Function(MemberPhotoService) action, {
    String? success,
  }) async {
    if (_busy) return false;
    final service = ref.read(memberPhotoServiceProvider);
    if (!_current(service)) return false;
    _busy = true;
    final previous = state.asData?.value ?? const MemberPhotoEditState();
    state = AsyncData(previous.working());
    final link = ref.keepAlive();
    try {
      await action(service);
      if (_current(service)) {
        state = AsyncData(await _read(service, success: success));
      }
      return _current(service);
    } catch (error) {
      final failure = error is MemberPhotoFailure
          ? error
          : const MemberPhotoFailure(
              'This photo action could not finish. Your saved selection has been retained.',
            );
      if (_current(service)) {
        try {
          state = AsyncData(await _read(service, error: failure));
        } catch (_) {
          state = AsyncData(
            MemberPhotoEditState(
              pending: previous.pending,
              preview: previous.preview,
              error: failure,
            ),
          );
        }
      }
      return false;
    } finally {
      _busy = false;
      link.close();
    }
  }

  Future<bool> choose(ImageSource source) => _run((service) async {
    await service.select(target, source);
  });
  Future<bool> cancel() {
    final knownNotCommitted =
        state.asData?.value.error?.code == 'PHOTO_CHANGED';
    return _run(
      (service) =>
          service.discard(target, knownNotCommitted: knownNotCommitted),
    );
  }

  Future<bool> upload() => _run((service) async {
    final receipt = await service.apply(target, (value) {
      if (_current(service)) {
        state = AsyncData(
          (state.asData?.value ?? const MemberPhotoEditState()).working(
            progress: value,
          ),
        );
      }
    });
    if (receipt != null && _current(service)) _refresh(receipt);
  }, success: 'Photo saved.');
  Future<bool> remove() => _run((service) async {
    await service.stageRemoval(target);
    final receipt = await service.apply(target, (_) {});
    if (receipt != null && _current(service)) _refresh(receipt);
  }, success: 'Photo removed.');
  void _refresh(MemberPhotoReceipt receipt) {
    ref.read(memberPhotoReceiptsProvider.notifier).save(target, receipt);
    final scope = (
      userId: target.scope.userId,
      gymId: target.scope.gymId,
      memberId: target.memberId!,
    );
    // Do not invalidate the editable profile: rebuilding its loading page would
    // discard unsaved text fields. Photo receipts update the avatar immediately.
    ref.invalidate(membersProvider);
    ref.invalidate(memberSummaryProvider(scope));
    ref.invalidate(outstandingDuesProvider);
  }
}

final memberPhotoControllerProvider = AsyncNotifierProvider.autoDispose
    .family<MemberPhotoController, MemberPhotoEditState, MemberPhotoTarget>(
      MemberPhotoController.new,
      retry: (_, _) => null,
    );

class MemberPhotoReceipts
    extends Notifier<Map<MemberPhotoTarget, MemberPhotoReceipt>> {
  @override
  Map<MemberPhotoTarget, MemberPhotoReceipt> build() {
    ref.watch(adminGymProvider);
    ref.watch(appConfigProvider);
    return const {};
  }

  void save(MemberPhotoTarget target, MemberPhotoReceipt receipt) =>
      state = {...state, target: receipt};
}

final memberPhotoReceiptsProvider =
    NotifierProvider<
      MemberPhotoReceipts,
      Map<MemberPhotoTarget, MemberPhotoReceipt>
    >(MemberPhotoReceipts.new);
