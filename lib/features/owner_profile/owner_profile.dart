import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/providers/auth_providers.dart';
import '../members/models/pending_onboarding.dart';
import '../members/photos/member_photo_models.dart';
import '../members/photos/member_photo_providers.dart';

class OwnerProfile {
  const OwnerProfile({
    required this.userId,
    required this.gymId,
    required this.name,
    required this.email,
    required this.phone,
    required this.gymName,
    required this.gymPhone,
    required this.gymEmail,
    required this.completed,
    required this.total,
    required this.photoRevision,
    this.photoUrl,
    this.sourceScope,
  });
  factory OwnerProfile.fromJson(Map<String, dynamic> data) {
    String text(String key) => data[key] as String;
    final completion = data['completion'] as Map;
    final result = OwnerProfile(
      userId: text('userId'),
      gymId: text('gymId'),
      name: text('displayName'),
      email: text('email'),
      phone: text('phone'),
      gymName: text('gymName'),
      gymPhone: text('gymContactPhone'),
      gymEmail: text('gymContactEmail'),
      completed: completion['completed'] as int,
      total: completion['total'] as int,
      photoRevision: data['photoRevision'] as int,
      photoUrl: data['photoUrl'] as String?,
    );
    if (result.total != 6 ||
        result.completed < 0 ||
        result.completed > result.total ||
        result.photoRevision < 0 ||
        result.photoUrl != null &&
            result.photoUrl !=
                'gyms/${result.gymId}/owner-profile/photo?v=${result.photoRevision}') {
      throw const FormatException('Invalid owner profile.');
    }
    return result;
  }
  final String userId, gymId, name, email, phone, gymName, gymPhone, gymEmail;
  final String? photoUrl, sourceScope;
  OwnerProfile inScope(String source) => OwnerProfile(
    userId: userId,
    gymId: gymId,
    name: name,
    email: email,
    phone: phone,
    gymName: gymName,
    gymPhone: gymPhone,
    gymEmail: gymEmail,
    completed: completed,
    total: total,
    photoRevision: photoRevision,
    photoUrl: photoUrl,
    sourceScope: source,
  );
  final int completed, total, photoRevision;
  double get completion => completed / total;
}

class OwnerProfileFailure implements Exception {
  const OwnerProfileFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class OwnerProfileRepository {
  Future<OwnerProfile> get(AdminGymContext scope, CancelToken cancel);
  Future<OwnerProfile> save(
    AdminGymContext scope,
    Map<String, String> input,
    CancelToken cancel,
  );
}

class DioOwnerProfileRepository implements OwnerProfileRepository {
  DioOwnerProfileRepository(this.client);
  final Dio client;
  Future<OwnerProfile> _request(
    AdminGymContext scope,
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final response = (await send()).data;
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! Map) {
        throw const FormatException();
      }
      final profile = OwnerProfile.fromJson(
        Map<String, dynamic>.from(response['data'] as Map),
      );
      if (profile.userId != scope.userId || profile.gymId != scope.gymId) {
        throw const FormatException();
      }
      return profile;
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map && data['error'] is Map
          ? data['error']['code']
          : null;
      throw OwnerProfileFailure(switch (code) {
        'PROFILE_PASSWORD_REQUIRED' =>
          'Enter your current password to change the sign-in email.',
        'PROFILE_PASSWORD_INVALID' =>
          'The current password is incorrect. Nothing was saved.',
        'DUPLICATE_EMAIL' =>
          'An account already uses that email. Choose another email.',
        'DUPLICATE_NAME' || 'DUPLICATE_GYM_NAME' =>
          'A gym already uses that name. Choose another name.',
        'PROFILE_CHANGED' =>
          'Your account changed. Reload your profile before saving again.',
        'FORBIDDEN' =>
          'You no longer have permission to edit this gym profile.',
        'VALIDATION_ERROR' =>
          'Check the name, email and phone fields, then try again.',
        'NOT_FOUND' =>
          'Owner profiles are not available on this server yet. Your existing account is unchanged.',
        _ =>
          'The profile could not be verified. Check your connection and retry.',
      });
    } catch (error) {
      if (error is OwnerProfileFailure) rethrow;
      throw const OwnerProfileFailure(
        'The profile response could not be verified. Please retry.',
      );
    }
  }

  @override
  Future<OwnerProfile> get(AdminGymContext scope, CancelToken cancel) =>
      _request(
        scope,
        () => client.get(
          'gyms/${scope.gymId}/owner-profile',
          cancelToken: cancel,
        ),
      );
  @override
  Future<OwnerProfile> save(
    AdminGymContext scope,
    Map<String, String> input,
    CancelToken cancel,
  ) => _request(
    scope,
    () => client.patch(
      'gyms/${scope.gymId}/owner-profile',
      data: input,
      cancelToken: cancel,
    ),
  );
}

final ownerProfileRepositoryProvider = Provider<OwnerProfileRepository>(
  (ref) => DioOwnerProfileRepository(ref.watch(authenticatedApiClientProvider)),
);
MemberPhotoTarget? ownerPhotoTarget(WidgetRef ref) {
  final gym = ref.watch(adminGymProvider);
  final config = ref.watch(appConfigProvider);
  if (gym == null || config.apiBaseUrl == null) return null;
  return MemberPhotoTarget.owner(
    OnboardingScope.fromConfig(config, userId: gym.userId, gymId: gym.gymId),
  );
}

final ownerProfileProvider = FutureProvider.autoDispose<OwnerProfile?>((
  ref,
) async {
  final scope = ref.watch(adminGymProvider);
  final config = ref.watch(appConfigProvider);
  if (scope == null || config.apiBaseUrl == null) return null;
  final target = MemberPhotoTarget.owner(
    OnboardingScope.fromConfig(
      config,
      userId: scope.userId,
      gymId: scope.gymId,
    ),
  );
  ref.watch(memberPhotoReceiptsProvider.select((items) => items[target]));
  final cancel = CancelToken();
  ref.onDispose(() => cancel.cancel());
  final profile = await ref
      .watch(ownerProfileRepositoryProvider)
      .get(scope, cancel);
  return profile.inScope(ownerProfileScopeKey(config, scope));
}, retry: (_, _) => null);

// Reuse authenticated, scope/revision-bound photo bytes, never a provider URL.
AsyncValue<Uint8List>? ownerPhotoImage(WidgetRef ref, OwnerProfile profile) {
  final target = ownerPhotoTarget(ref);
  return target == null || profile.photoUrl == null
      ? null
      : ref.watch(
          memberPhotoImageProvider((target: target, url: profile.photoUrl!)),
        );
}

String ownerProfileScopeKey(AppConfig config, AdminGymContext scope) =>
    '${config.environment.name}|${config.apiBaseUrl}|${scope.userId}|${scope.gymId}';

OwnerProfile? currentOwnerProfile(WidgetRef ref) {
  final value = ref.watch(ownerProfileProvider).value;
  final scope = ref.watch(adminGymProvider);
  final config = ref.watch(appConfigProvider);
  return value != null &&
          scope != null &&
          value.userId == scope.userId &&
          value.gymId == scope.gymId &&
          value.sourceScope == ownerProfileScopeKey(config, scope)
      ? value
      : null;
}
