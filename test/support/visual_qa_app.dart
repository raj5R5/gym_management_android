import 'package:gym_management_app/features/members/photos/member_photo_providers.dart';
import '../features/members/photo_fakes.dart';
// Emulator-only launcher for inspecting the real routed Flutter UI with the
// existing synthetic repositories. Production main.dart never imports this file.
// Run: flutter run -t test/support/visual_qa_app.dart -d emulator-5554
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/app/router/app_router.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';
import 'package:gym_management_app/features/members/data/pending_onboarding_store.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';
import 'package:gym_management_app/features/members/providers/member_providers.dart';
import 'package:gym_management_app/features/members/providers/onboarding_providers.dart';
import 'package:gym_management_app/features/memberships/data/pending_payment_store.dart';
import 'package:gym_management_app/features/memberships/providers/membership_providers.dart';
import 'package:gym_management_app/features/memberships/providers/payment_providers.dart';
import 'package:gym_management_app/features/trainers/providers/trainer_providers.dart';
import '../features/auth/auth_fakes.dart';
import '../features/admin_dashboard/dashboard_fakes.dart';
import '../features/members/member_fakes.dart';
import '../features/members/onboarding_fakes.dart';
import '../features/memberships/billing_fakes.dart';
import '../features/memberships/payment_fakes.dart';
import '../features/trainers/trainer_fakes.dart';

class VisualMembers extends DueMembersFake {
  VisualMembers() {
    profiles = [
      for (final row in [
        ('000000000000000000000011', 'Meera', 'Nair', 'M036'),
        ('000000000000000000000012', 'Ananya', 'Rao', 'M014'),
        ('000000000000000000000013', 'Vikram', 'Sen', 'M041'),
        ('000000000000000000000014', 'Rohan', 'Shah', 'M028'),
      ])
        MemberProfile.fromJson({
          ...profileJson(),
          'id': row.$1,
          'firstName': row.$2,
          'lastName': row.$3,
          'memberCode': row.$4,
        }),
    ];
    debts.clear();
    for (var i = 0; i < profiles.length; i++) {
      final balance = [0, 85000, 150000, 250000][i];
      debts[profiles[i].id] = [
        debtJson(
          id: '00000000000000000000002${i + 2}',
          balance: balance,
          status: i == 2 ? 'expired' : 'active',
        )..addAll({
          'pricePaiseSnapshot': 500000,
          'startDate': i == 2 ? '2026-09-01' : '2026-10-01',
          'endDate': i == 2 ? '2026-10-01' : '2026-10-31',
          'paymentSummary': {
            'totalSuccessfulPaidPaise': 500000 - balance,
            'remainingBalancePaise': balance,
          },
        }),
      ];
    }
  }

  @override
  Future<MemberSummary> summary(String gymId, String id) async {
    final member = profiles.firstWhere((m) => m.id == id);
    final all = debts[id] ?? [];
    final current = all
        .where((m) => m['isCurrentlyActive'] == true)
        .firstOrNull;
    final money = current?['paymentSummary'] as Map?;
    return MemberSummary.fromJson(
      summaryJson(populated: true)..addAll({
        'member': {
          ...profileJson(),
          'id': member.id,
          'memberCode': member.memberCode,
          'firstName': member.firstName,
          'lastName': member.lastName,
        },
        'currentSubscription': current,
        'currentSubscriptionPaymentSummary': money == null
            ? null
            : {
                'pricePaise': current!['pricePaiseSnapshot'],
                'paidAmountPaise': money['totalSuccessfulPaidPaise'],
                'remainingAmountPaise': money['remainingBalancePaise'],
                'paymentCount': 1,
              },
        'subscriptionHistory': {
          'items': all,
          'page': 1,
          'limit': 20,
          'total': all.length,
        },
      }),
    );
  }
}

void main() {
  if (kReleaseMode) throw StateError('Visual QA launcher is debug-only.');
  WidgetsFlutterBinding.ensureInitialized();
  final members = VisualMembers();
  final payments = FakePaymentRepository()..onCollection = members.collect;
  final storage = TestOnboardingStorage();
  const route = String.fromEnvironment('QA_ROUTE');
  const signedOut = bool.fromEnvironment('QA_SIGNED_OUT');
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.fromValues(apiBaseUrl: onboardingUrl),
      ),
      authApiServiceProvider.overrideWithValue(
        FakeAuthApi()..identity = adminIdentity(),
      ),
      credentialStorageProvider.overrideWithValue(
        FakeCredentialStorage()
          ..value = signedOut ? null : syntheticCredential(),
      ),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      memberRepositoryProvider.overrideWithValue(members),
      membershipRepositoryProvider.overrideWithValue(
        FakeMembershipRepository(),
      ),
      paymentRepositoryProvider.overrideWithValue(payments),
      trainerRepositoryProvider.overrideWithValue(FakeTrainerRepository()),
      memberOnboardingRepositoryProvider.overrideWithValue(
        FakeOnboardingRepository(),
      ),
      memberPhotoStoreProvider.overrideWithValue(MemoryMemberPhotoStore()),
      pendingOnboardingStoreProvider.overrideWithValue(
        SecurePendingOnboardingStore(
          storage: storage,
          queue: OnboardingOperationQueue(),
        ),
      ),
      pendingPaymentStoreProvider.overrideWithValue(
        PendingPaymentStore(
          storage: storage,
          queue: OnboardingOperationQueue(),
        ),
      ),
    ],
  );
  registerExtension('ext.gym.visual.route', (method, parameters) async {
    final route = parameters['route'];
    if (parameters['signOut'] == 'true') {
      await container.read(sessionControllerProvider.notifier).logout();
    }
    if (route != null) container.read(appRouterProvider).go(route);
    return ServiceExtensionResponse.result(jsonEncode({'ok': true}));
  });
  var routed = false;
  container.listen(sessionControllerProvider, (_, next) {
    if (next is SessionAuthenticated && route.isNotEmpty && !routed) {
      routed = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => container.read(appRouterProvider).go(route),
      );
    }
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const GymApp()),
  );
}
