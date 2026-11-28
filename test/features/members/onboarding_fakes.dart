import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/members/data/member_onboarding_repository.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';
import 'member_fakes.dart';

const onboardingPlanId = '000000000000000000000033';
const onboardingOperationId = '000000000000000000000099';
const onboardingPaymentId = '000000000000000000000066';
const onboardingUrl = 'https://api.example.invalid/api/v1/';
OnboardingScope onboardingScope({
  String userId = 'test-account',
  String gymId = gymA,
  String url = onboardingUrl,
  AppEnvironment environment = AppEnvironment.development,
}) => OnboardingScope(
  environment: environment,
  apiBaseUrl: url,
  userId: userId,
  gymId: gymId,
);
OnboardingRequest onboardingRequest({
  bool membership = false,
  int? amount,
  PaymentMethod method = PaymentMethod.cash,
  String reference = '',
  DateTime? paidAt,
}) => OnboardingRequest(
  member: MemberDraft(
    memberCode: ' me01 ',
    firstName: ' Alex ',
    lastName: 'River',
    phone: '9876543210',
  ),
  membership: !membership
      ? null
      : OnboardingMembership(
          planId: onboardingPlanId,
          startDate: CalendarDate(2026, 1, 1),
          payment: amount == null
              ? null
              : OnboardingPayment(
                  method: method,
                  amountPaise: amount,
                  paidAt: paidAt ?? DateTime.utc(2026, 1, 1, 10),
                  reference: reference,
                ),
        ),
);
PendingOnboardingOperation pendingOperation({
  OnboardingRequest? request,
  OnboardingScope? scope,
}) {
  // Explicit legacy fixture for schema/storage compatibility tests. Obtain fresh
  // synthetic identity metadata without changing any restored record.
  final fresh = preparedOperation(request: request, scope: scope);
  return PendingOnboardingOperation(
    scope: fresh.scope,
    request: fresh.request,
    idempotencyKey: fresh.idempotencyKey,
    createdAt: fresh.createdAt,
  );
}

PendingOnboardingOperation preparedOperation({
  OnboardingRequest? request,
  OnboardingScope? scope,
}) => PendingOnboardingOperation.create(
  scope: scope ?? onboardingScope(),
  request: request ?? onboardingRequest(),
);

Map<String, dynamic> onboardingResultJson(
  OnboardingRequest request, {
  String gymId = gymA,
  int price = 150000,
}) {
  final body = request.toJson();
  final member = body['member'] as Map<String, dynamic>;
  final membership = body['membership'] as Map<String, dynamic>?;
  final initial = membership?['payment'] as Map<String, dynamic>?;
  final amount = (initial?['amountPaise'] as int?) ?? 0;
  return {
    'operationId': onboardingOperationId,
    'member': {
      'id': memberId,
      'gymId': gymId,
      // Like the server: a member sent without a code is numbered.
      'memberCode': (member['memberCode'] ?? 'M0001')
          .toString()
          .trim()
          .toUpperCase(),
      'firstName': member['firstName'].toString().trim(),
      'lastName': member['lastName'].toString().trim(),
      if (member['branchId'] != null) 'branchId': member['branchId'],
      'status': 'active',
    },
    'subscription': membership == null
        ? null
        : {
            'id': subscriptionId,
            'membershipPlanId': membership['planId'],
            'planNameSnapshot': 'Monthly',
            'durationDaysSnapshot': 30,
            'pricePaiseSnapshot': price,
            'startDate': membership['startDate'] ?? '2026-01-01',
            'endDate': '2026-01-31',
            'status': 'expired',
            'isCurrentlyActive': false,
          },
    'payment': amount == 0
        ? null
        : {
            'id': onboardingPaymentId,
            'subscriptionId': subscriptionId,
            'amountPaise': amount,
            'paymentMethod': initial!['method'],
            // Simulate the backend's Mongoose Date cast and JSON serialization.
            'paidAt': DateTime.fromMillisecondsSinceEpoch(
              DateTime.parse(
                initial['paidAt'] as String,
              ).millisecondsSinceEpoch,
              isUtc: true,
            ).toIso8601String(),
            if (initial['reference'] != null)
              'transactionReference': initial['reference'],
          },
    'billing': <String, dynamic>{
      'planPricePaise': membership == null ? 0 : price,
      'discountPaise': 0,
      'amountReceivedPaise': amount,
      'outstandingBalancePaise': (membership == null ? 0 : price) - amount,
    },
  };
}

class FakeOnboardingRepository implements MemberOnboardingRepository {
  final calls =
      <({String gymId, String body, String key, CancelToken? cancel})>[];
  Object? failure;
  Completer<OnboardingResult>? gate;
  @override
  Future<OnboardingResult> complete(
    String gymId,
    OnboardingRequest request,
    String idempotencyKey, {
    CancelToken? cancelToken,
  }) async {
    calls.add((
      gymId: gymId,
      body: request.frozenJson,
      key: idempotencyKey,
      cancel: cancelToken,
    ));
    if (failure != null) throw failure!;
    if (gate != null) return gate!.future;
    return OnboardingResult.fromJson(
      onboardingResultJson(request, gymId: gymId),
    );
  }
}

/// Exercises the real secure adapter without a platform or production records.
class TestOnboardingStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failRead = false, failWrite = false, failDelete = false;
  int writes = 0;
  Completer<void>? readGate, writeGate, writeEntered;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readGate != null) await readGate!.future;
    if (failRead) throw StateError('Synthetic storage read failure');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    if (writeEntered != null && !writeEntered!.isCompleted) {
      writeEntered!.complete();
    }
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('Synthetic storage write failure');
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDelete) throw StateError('Synthetic storage delete failure');
    values.remove(key);
  }
}
