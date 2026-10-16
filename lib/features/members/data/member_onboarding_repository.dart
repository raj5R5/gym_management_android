import 'package:dio/dio.dart';
import '../models/member_models.dart';
import '../models/onboarding_models.dart';
import 'onboarding_failure.dart';

abstract interface class MemberOnboardingRepository {
  Future<OnboardingResult> complete(
    String gymId,
    OnboardingRequest request,
    String idempotencyKey, {
    CancelToken? cancelToken,
  });
}

/// Transport only. The submission service persists before calling this method.
class DioMemberOnboardingRepository implements MemberOnboardingRepository {
  DioMemberOnboardingRepository(this._client);
  final Dio _client;
  @override
  Future<OnboardingResult> complete(
    String gymId,
    OnboardingRequest request,
    String idempotencyKey, {
    CancelToken? cancelToken,
  }) async {
    try {
      onboardingId(gymId);
      validateOnboardingKey(idempotencyKey);
    } catch (_) {
      throw const OnboardingFailure(OnboardingFailureKind.validation);
    }
    try {
      final response = await _client.post<dynamic>(
        'gyms/$gymId/member-onboarding/complete',
        data: request.toJson(),
        cancelToken: cancelToken,
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final envelope = object(response.data);
      if (response.statusCode != 201 || envelope['success'] != true) {
        throw const FormatException('Invalid onboarding envelope.');
      }
      text(object(envelope['meta']), 'requestId');
      final result = OnboardingResult.fromJson(object(envelope['data']));
      result.validateFor(gymId, request);
      return result;
    } on DioException catch (error) {
      throw OnboardingFailure.fromDio(error);
    } catch (_) {
      throw const OnboardingFailure(
        OnboardingFailureKind.unexpectedResponse,
        uncertain: true,
      );
    }
  }
}
