import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';

enum OnboardingFailureKind {
  validation,
  authorization,
  conflict,
  resourceNotFound,
  rateLimited,
  configuration,
  retryRequired,
  network,
  storageUnavailable,
  server,
  unexpectedResponse,
  localStorage,
  corruptRecord,
  unsupportedVersion,
  scopeMismatch,
  pendingOperation,
}

/// Codes supported by the onboarding endpoint and shared error middleware.
/// The status and category are part of the contract, not inferred from a 4xx.
enum OnboardingBackendCode {
  validationError('VALIDATION_ERROR', 400, OnboardingFailureKind.validation),
  minorWorkflowUnavailable(
    'MINOR_MEMBER_WORKFLOW_UNAVAILABLE',
    409,
    OnboardingFailureKind.validation,
  ),
  invalidJson('INVALID_JSON', 400, OnboardingFailureKind.validation),
  paymentMemberMismatch(
    'PAYMENT_MEMBER_MISMATCH',
    400,
    OnboardingFailureKind.validation,
  ),
  payloadTooLarge('PAYLOAD_TOO_LARGE', 413, OnboardingFailureKind.validation),
  unsupportedEncoding(
    'UNSUPPORTED_ENCODING',
    415,
    OnboardingFailureKind.validation,
  ),
  invalidAuthentication(
    'INVALID_AUTHENTICATION',
    401,
    OnboardingFailureKind.authorization,
  ),
  invalidCredentials(
    'INVALID_CREDENTIALS',
    401,
    OnboardingFailureKind.authorization,
  ),
  forbidden('FORBIDDEN', 403, OnboardingFailureKind.authorization),
  corsOriginDenied(
    'CORS_ORIGIN_DENIED',
    403,
    OnboardingFailureKind.authorization,
  ),
  planNotFound('PLAN_NOT_FOUND', 404, OnboardingFailureKind.resourceNotFound),
  branchNotFound(
    'BRANCH_NOT_FOUND',
    404,
    OnboardingFailureKind.resourceNotFound,
  ),
  memberNotFound(
    'MEMBER_NOT_FOUND',
    404,
    OnboardingFailureKind.resourceNotFound,
  ),
  subscriptionNotFound(
    'SUBSCRIPTION_NOT_FOUND',
    404,
    OnboardingFailureKind.resourceNotFound,
  ),
  notFound('NOT_FOUND', 404, OnboardingFailureKind.configuration),
  idempotencyKeyConflict(
    'IDEMPOTENCY_KEY_CONFLICT',
    409,
    OnboardingFailureKind.conflict,
  ),
  duplicateMemberCode(
    'DUPLICATE_MEMBER_CODE',
    409,
    OnboardingFailureKind.conflict,
  ),
  duplicatePaymentReference(
    'DUPLICATE_PAYMENT_REFERENCE',
    409,
    OnboardingFailureKind.conflict,
  ),
  paymentOverpayment(
    'PAYMENT_OVERPAYMENT',
    409,
    OnboardingFailureKind.conflict,
  ),
  paymentSubscriptionCancelled(
    'PAYMENT_SUBSCRIPTION_CANCELLED',
    409,
    OnboardingFailureKind.conflict,
  ),
  subscriptionOverlap(
    'SUBSCRIPTION_OVERLAP',
    409,
    OnboardingFailureKind.conflict,
  ),
  rateLimited('RATE_LIMITED', 429, OnboardingFailureKind.rateLimited),
  onboardingStorageUnavailable(
    'ONBOARDING_STORAGE_UNAVAILABLE',
    503,
    OnboardingFailureKind.storageUnavailable,
  );

  const OnboardingBackendCode(this.wireValue, this.status, this.kind);
  final String wireValue;
  final int status;
  final OnboardingFailureKind kind;
}

/// A recognized backend response. This never establishes the outcome of earlier
/// attempts. In particular, a key conflict indicates an existing operation.
class OnboardingBackendRejection {
  const OnboardingBackendRejection._(this.code);
  final OnboardingBackendCode code;
  int get status => code.status;
  bool get establishesAttemptNonCommit =>
      code != OnboardingBackendCode.idempotencyKeyConflict;

  static OnboardingBackendRejection? tryFrom(Object? code, Object? status) {
    if (code is! String || status is! int) return null;
    for (final recognized in OnboardingBackendCode.values) {
      if (recognized.wireValue == code && recognized.status == status) {
        return OnboardingBackendRejection._(recognized);
      }
    }
    return null;
  }

  factory OnboardingBackendRejection.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        json['type'] != 'backendRejection' ||
        !json.keys.toSet().containsAll({'type', 'code', 'status'})) {
      throw const FormatException('Invalid backend rejection evidence.');
    }
    final reason = tryFrom(json['code'], json['status']);
    if (reason == null) {
      throw const FormatException('Unknown or inconsistent backend rejection.');
    }
    return reason;
  }

  Map<String, dynamic> toJson() => {
    'type': 'backendRejection',
    'code': code.wireValue,
    'status': status,
  };
}

/// Ephemeral transport diagnostics, separate from durable non-commit evidence.
/// Only fixed public messages from the API contract may leave this boundary.
/// Arbitrary backend text can contain credentials, PII or payment references.
class OnboardingDiagnostics {
  const OnboardingDiagnostics._(this.httpStatus, this.code, this.serverMessage);
  final int? httpStatus;
  final String? code, serverMessage;

  static const _publicMessages = <String, String>{
    'MINOR_MEMBER_WORKFLOW_UNAVAILABLE':
        'Under-18 registration, profile changes and photo uploads are unavailable until guardian authorization and verification are supported.',
    'INVALID_JSON': 'Request body must contain valid JSON.',
    'PAYLOAD_TOO_LARGE': 'Request body exceeds the allowed size.',
    'UNSUPPORTED_ENCODING': 'Request encoding is not supported.',
    'PAYMENT_MEMBER_MISMATCH':
        'Subscription does not belong to the specified member.',
    'PAYMENT_SUBSCRIPTION_CANCELLED':
        'Cannot record payment against a cancelled subscription.',
    'INVALID_AUTHENTICATION': 'Authentication is invalid or expired.',
    'INVALID_CREDENTIALS': 'Invalid email or password.',
    'CORS_ORIGIN_DENIED': 'Origin is not allowed.',
    'NOT_FOUND': 'Route not found.',
    'MEMBER_NOT_FOUND': 'Member not found.',
    'SUBSCRIPTION_NOT_FOUND': 'Subscription not found.',
    'DUPLICATE_MEMBER_CODE': 'Member code already exists in this gym.',
    'DUPLICATE_PAYMENT_REFERENCE':
        'A successful payment with this reference already exists for this method in this gym.',
    'IDEMPOTENCY_KEY_CONFLICT':
        'This idempotency key was already used with a different request.',
    'PAYMENT_OVERPAYMENT': 'Payment exceeds the remaining subscription amount.',
    'SUBSCRIPTION_OVERLAP':
        'Subscription period overlaps an existing non-cancelled subscription.',
    'FORBIDDEN': 'You do not have permission to perform this operation.',
    'VALIDATION_ERROR': 'Request validation failed.',
    'PLAN_NOT_FOUND': 'Membership plan not found.',
    'BRANCH_NOT_FOUND': 'Branch not found.',
    'ONBOARDING_STORAGE_UNAVAILABLE':
        'Combined onboarding requires transaction-capable database storage.',
    'INTERNAL_SERVER_ERROR': 'An unexpected server error occurred.',
    'RATE_LIMITED': 'Too many requests. Please try again later.',
  };

  factory OnboardingDiagnostics.fromResponse(int? status, Object? body) {
    final validStatus = status != null && status >= 100 && status <= 599
        ? status
        : null;
    final error = body is Map && body['success'] == false
        ? body['error']
        : null;
    final candidate = error is Map ? error['code'] : null;
    final recognized = OnboardingBackendRejection.tryFrom(
      candidate,
      validStatus,
    );
    final code =
        recognized?.code.wireValue ??
        (candidate == 'INTERNAL_SERVER_ERROR' && validStatus == 500
            ? 'INTERNAL_SERVER_ERROR'
            : null);
    final expected = _publicMessages[code];
    final message = error is Map ? error['message'] : null;
    return OnboardingDiagnostics._(
      validStatus,
      code,
      expected != null && message == expected ? expected : null,
    );
  }

  String get summary => [
    if (httpStatus != null) 'HTTP $httpStatus',
    ?code,
    ?serverMessage,
  ].join(' · ');
}

class OnboardingFailure implements Exception {
  const OnboardingFailure(
    this.kind, {
    this.uncertain = false,
    this.backendRejection,
    this.diagnostics,
  });
  final OnboardingFailureKind kind;
  final OnboardingDiagnostics? diagnostics;

  /// Absent for generic categories, auth wrappers and unrecognized responses.
  final OnboardingBackendRejection? backendRejection;

  /// This failure does not establish whether the attempt committed.
  ///
  /// Even a definite rejection of a retry cannot rule out an earlier commit.
  /// Retain the saved operation and recover only with its original body and key.
  final bool uncertain;
  String get message => switch (kind) {
    OnboardingFailureKind.validation =>
      'Check the member, membership and payment information.',
    OnboardingFailureKind.authorization =>
      'Sign in with an authorized administrator for this gym.',
    OnboardingFailureKind.conflict =>
      'The request conflicts with an existing record or operation. Do not start a duplicate submission.',
    OnboardingFailureKind.resourceNotFound =>
      'A resource required for onboarding is unavailable. The saved submission has been retained.',
    OnboardingFailureKind.rateLimited =>
      'Too many requests. Wait before retrying the saved submission.',
    OnboardingFailureKind.configuration =>
      'The API connection is not configured. The saved submission has been retained.',
    OnboardingFailureKind.retryRequired =>
      'Your session was recovered. Retry using the saved submission.',
    OnboardingFailureKind.network =>
      'The outcome is uncertain. Recover using the saved submission.',
    OnboardingFailureKind.storageUnavailable =>
      'Combined onboarding requires transaction-capable backend storage.',
    OnboardingFailureKind.server =>
      'The service is unavailable. Recover using the saved submission.',
    OnboardingFailureKind.unexpectedResponse =>
      'Confirmation could not be verified. Recover using the saved submission.',
    OnboardingFailureKind.localStorage =>
      'Secure storage could not be accessed.',
    OnboardingFailureKind.corruptRecord =>
      'The saved operation is unreadable. It has been retained; do not create a duplicate.',
    OnboardingFailureKind.unsupportedVersion =>
      'The saved operation requires a compatible app version. It has been retained.',
    OnboardingFailureKind.scopeMismatch =>
      'This operation belongs to a different account, gym or API environment.',
    OnboardingFailureKind.pendingOperation =>
      'Resolve the existing saved operation before starting another.',
  };

  factory OnboardingFailure.fromDio(DioException error) {
    final diagnostics = OnboardingDiagnostics.fromResponse(
      error.response?.statusCode,
      error.response?.data,
    );
    if (error.error case final AuthFailure failure) {
      // Auth wrappers have no final onboarding response or execution-stage
      // information. Preserve the cause without inferring an operation rollback.
      final kind = switch (failure.kind) {
        AuthFailureKind.invalidCredentials ||
        AuthFailureKind.invalidSession ||
        AuthFailureKind.forbidden => OnboardingFailureKind.authorization,
        AuthFailureKind.validation => OnboardingFailureKind.validation,
        AuthFailureKind.rateLimited ||
        AuthFailureKind.locked => OnboardingFailureKind.rateLimited,
        AuthFailureKind.network => OnboardingFailureKind.network,
        AuthFailureKind.server => OnboardingFailureKind.server,
        AuthFailureKind.unexpectedResponse =>
          OnboardingFailureKind.unexpectedResponse,
        AuthFailureKind.storage => OnboardingFailureKind.localStorage,
        AuthFailureKind.configuration => OnboardingFailureKind.configuration,
        AuthFailureKind.retryRequired => OnboardingFailureKind.retryRequired,
      };
      return OnboardingFailure(kind, uncertain: true, diagnostics: diagnostics);
    }
    final body = error.response?.data;
    final code = body is Map && body['success'] == false && body['error'] is Map
        ? (body['error'] as Map)['code']
        : null;
    final status = error.response?.statusCode;
    final rejection = OnboardingBackendRejection.tryFrom(code, status);
    if (rejection != null) {
      return OnboardingFailure(
        rejection.code.kind,
        backendRejection: rejection,
        diagnostics: diagnostics,
      );
    }
    if (status != null && status >= 500) {
      return OnboardingFailure(
        OnboardingFailureKind.server,
        uncertain: true,
        diagnostics: diagnostics,
      );
    }
    if (error.response == null) {
      return OnboardingFailure(
        OnboardingFailureKind.network,
        uncertain: true,
        diagnostics: diagnostics,
      );
    }
    return OnboardingFailure(
      OnboardingFailureKind.unexpectedResponse,
      uncertain: true,
      diagnostics: diagnostics,
    );
  }
  @override
  String toString() => 'OnboardingFailure(${kind.name}): $message';
}
