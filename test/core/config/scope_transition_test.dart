import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import '../../features/admin_dashboard/dashboard_fakes.dart';
import '../../features/members/member_fakes.dart';
import '../../features/members/onboarding_fakes.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/members/models/pending_onboarding.dart';

void main() {
  test('legacy branch request and receipt survive recovery byte-for-byte', () {
    final body = onboardingRequest().toJson();
    (body['member'] as Map)['branchId'] = '000000000000000000000044';
    final frozen = const JsonEncoder.withIndent('  ').convert(body);
    final request = OnboardingRequest.fromFrozenJson(frozen);
    final receipt = OnboardingResult.fromJson(onboardingResultJson(request));
    receipt.validateFor(onboardingScope().gymId, request);
    final prepared = PendingOnboardingOperation.create(
      scope: onboardingScope(),
      request: request,
    );
    expect(
      PendingOnboardingOperation.decode(prepared.encode()).request.frozenJson,
      frozen,
    );
    final operation = pendingOperation(request: request);
    final restored = PendingOnboardingOperation.decode(operation.encode());
    expect(restored.request.frozenJson, frozen);
    expect(restored.idempotencyKey, operation.idempotencyKey);
    final confirmed = restored.confirmed(receipt);
    final reread = PendingOnboardingOperation.decode(confirmed.encode());
    expect(reread.result!.toJson(), receipt.toJson());
    expect(reread.request.frozenJson, frozen);
  });
  for (final legacy in [false, true]) {
    test(
      'dashboard reads ${legacy ? "legacy" : "retired-feature-free"} response',
      () {
        final json = dashboardJson();
        if (!legacy) {
          json.remove('attendance');
          (json['period'] as Map).remove('branchId');
        }
        final value = GymDashboard.fromJson(json);
        expect(value.members.total, 12);
        expect(value.payments.outstandingAmountPaise, 50000);
      },
    );
    test(
      'member summary reads ${legacy ? "legacy" : "retired-feature-free"} response',
      () {
        final json = summaryJson(populated: true);
        if (!legacy) {
          json.remove('attendanceSummary');
          json.remove('currentBranch');
          (json['member'] as Map).remove('branchId');
        }
        final value = MemberSummary.fromJson(json);
        expect(value.trainers.single.name, 'Pat Lee');
        expect(value.currentPayments!.balancePaise, 149697);
      },
    );
  }
  test('retired data does not determine dashboard emptiness', () {
    final json = dashboardJson(empty: true);
    json['attendance'] = {
      'periodVisits': 9,
      'periodUniqueMembers': 4,
      'currentlyCheckedIn': 1,
    };
    expect(GymDashboard.fromJson(json).isEmpty, isTrue);
  });
}
