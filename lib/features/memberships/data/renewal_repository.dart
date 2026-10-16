import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';
import '../../members/models/member_models.dart';
import '../models/renewal_operation.dart';
import '../models/renewal_preview.dart';
import 'billing_failure.dart';
import 'pending_renewal_store.dart' show renewalRejections;

abstract interface class RenewalRepository {
  Future<RenewalPreview> preview(
    String gymId,
    String memberId,
    String predecessorId,
    String planId,
  );
  Future<RenewalResult> complete(
    String gymId,
    String memberId,
    String predecessorId,
    RenewalOperationRequest request, {
    CancelToken? cancelToken,
  });
}

class DioRenewalRepository implements RenewalRepository {
  DioRenewalRepository(this._client);
  final Dio _client;
  void _ids(List<String> ids) {
    if (ids.any((id) => !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id))) {
      throw const BillingFailure('Invalid renewal context.');
    }
  }

  @override
  Future<RenewalPreview> preview(
    String gymId,
    String memberId,
    String predecessorId,
    String planId,
  ) async {
    _ids([gymId, memberId, predecessorId, planId]);
    try {
      final envelope = object(
        (await _client.get(
          'gyms/$gymId/subscriptions/$predecessorId/renewal-preview',
          queryParameters: {'planId': planId},
        )).data,
      );
      if (envelope['success'] != true) {
        throw const FormatException('Invalid envelope.');
      }
      final result = RenewalPreview.fromJson(object(envelope['data']));
      if (result.gymId != gymId ||
          result.memberId != memberId ||
          result.subscriptionId != predecessorId ||
          result.planId != planId) {
        throw const FormatException('Preview scope mismatch.');
      }
      return result;
    } on DioException catch (error) {
      throw BillingFailure.fromDio(error, writing: false);
    } catch (error) {
      if (error is BillingFailure) rethrow;
      throw const BillingFailure(
        'Renewal preview could not be verified. Please reload.',
      );
    }
  }

  @override
  Future<RenewalResult> complete(
    String gymId,
    String memberId,
    String predecessorId,
    RenewalOperationRequest request, {
    CancelToken? cancelToken,
  }) async {
    _ids([gymId, memberId, predecessorId]);
    try {
      final envelope = object(
        (await _client.post(
          'gyms/$gymId/subscriptions/$predecessorId/renew',
          data: request.body,
          options: Options(headers: {'Idempotency-Key': request.key}),
          cancelToken: cancelToken,
        )).data,
      );
      if (envelope['success'] != true) {
        throw const FormatException('Invalid envelope.');
      }
      final result = RenewalResult.fromJson(object(envelope['data']));
      request.validateResult(
        result,
        gymId: gymId,
        memberId: memberId,
        predecessorId: predecessorId,
      );
      return result;
    } on DioException catch (error) {
      final body = error.response?.data;
      final code = body is Map && body['error'] is Map
          ? body['error']['code']
          : null;
      final status = error.response?.statusCode;
      if (code == 'IDEMPOTENCY_KEY_CONFLICT' && status == 409) {
        throw const BillingFailure(
          'This saved renewal conflicts with another operation. Check membership and payment history; do not renew again.',
          uncertain: true,
          code: 'IDEMPOTENCY_KEY_CONFLICT',
          httpStatus: 409,
        );
      }
      if (error.error is AuthFailure ||
          code is! String ||
          renewalRejections[code] != status) {
        throw const BillingFailure(
          'Renewal outcome is uncertain. Retry the saved renewal exactly; do not collect money again.',
          uncertain: true,
        );
      }
      final safe = BillingFailure.fromDio(error, writing: true);
      throw BillingFailure(safe.message, code: code, httpStatus: status);
    } catch (error) {
      if (error is BillingFailure) rethrow;
      throw const BillingFailure(
        'Renewal result could not be verified. Recover the saved renewal.',
        uncertain: true,
      );
    }
  }
}
