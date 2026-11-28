import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/member_app/activation_page.dart';
import 'package:gym_management_app/features/member_app/member_access.dart';
import 'package:gym_management_app/features/member_app/member_home.dart';
import 'package:gym_management_app/features/member_app/member_home_page.dart';
import 'package:gym_management_app/features/member_app/payment_claims.dart';
import 'package:gym_management_app/features/admin_dashboard/providers/dashboard_providers.dart';
import 'package:gym_management_app/features/members/models/member_models.dart';

const gymId = '0000000000000000000000f1';
const memberId = '0000000000000000000000d1';
const code = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde';

Map<String, dynamic> homeJson({
  Map<String, dynamic>? membership = const {
    'state': 'active',
    'planName': 'Monthly',
    'startDate': '2026-11-01',
    'endDate': '2026-12-01',
    'daysLeft': 15,
    'daysSinceExpiry': 0,
    'expiringSoon': false,
    'renewedAhead': false,
    'frozenUntil': null,
  },
  int balance = 50000,
}) => {
  'today': '2026-11-16',
  'gym': {
    'name': 'Iron Gym',
    'phone': '9876543210',
    'address': 'MG Road, Pune',
    'upiId': 'iron@okaxis',
    'upiPayeeName': 'Iron Gym',
  },
  'member': {
    'id': memberId,
    'memberCode': 'ME001',
    'firstName': 'Riya',
    'lastName': 'Shah',
  },
  'membership': membership,
  'dues': {
    'balancePaise': balance,
    'dueSubscriptionId': balance > 0 ? 's1' : null,
  },
  'visits': {
    'thisMonth': 6,
    'lastVisitDate': '2026-11-16',
    'visitedToday': true,
    'weekStreak': 4,
    'recent': ['2026-11-16'],
  },
  'pt': [
    {
      'id': 'p1',
      'name': 'PT 12',
      'trainerName': 'Vikram Rao',
      'sessionsTotal': 12,
      'sessionsUsed': 3,
      'sessionsLeft': 9,
      'expiresOn': null,
      'expired': false,
      'balancePaise': 0,
    },
  ],
};

class _FakeHome implements MemberHomeRepository {
  _FakeHome(this.json);
  final Map<String, dynamic> json;
  final calls = <String>[];
  @override
  Future<void> reportUpiPayment(
    String gymId, {
    required int amountPaise,
    required String reference,
  }) async {
    calls.add('claim:$amountPaise:$reference');
    (json['dues'] as Map)['pendingClaimPaise'] = amountPaise;
  }

  @override
  Future<MemberHome> home(String gymId) async => MemberHome.fromJson(json);
  List<Map<String, dynamic>> claimRows = [];
  @override
  Future<List<MemberClaim>> claims(String gymId) async => [
    for (final row in claimRows) MemberClaim.fromJson(row),
  ];

  @override
  Future<List<MemberPaymentEntry>> payments(String gymId) async => [
    MemberPaymentEntry.fromJson({
      'id': 'pay1',
      'amountPaise': 100000,
      'paymentMethod': 'upi',
      'paidAt': '2026-11-01T10:00:00.000Z',
    }),
  ];
}

class _FakeAccess implements MemberAccessRepository {
  MemberAccessState state = MemberAccessState.fromJson({
    'provisioned': false,
    'gymAccess': null,
    'activated': false,
  });
  final calls = <String>[];
  @override
  Future<MemberAccessState> get(String gymId, String memberId) async => state;
  @override
  Future<ActivationCode?> give(
    String gymId,
    String memberId, {
    required String email,
    required String displayName,
  }) async {
    calls.add('give:$email:$displayName');
    state = MemberAccessState.fromJson({
      'provisioned': true,
      'email': email,
      'gymAccess': {'role': 'member', 'status': 'active'},
      'activated': false,
    });
    return (code: code, expiresAt: DateTime(2026, 11, 19, 10), email: email);
  }

  @override
  Future<ActivationCode> newCode(String gymId, String memberId) async {
    calls.add('new');
    return (
      code: code,
      expiresAt: DateTime(2026, 11, 19, 10),
      email: 'r@x.com',
    );
  }

  @override
  Future<void> turnOff(String gymId, String memberId) async => calls.add('off');
}

class _FakeActivation implements ActivationRepository {
  final calls = <String>[];
  @override
  Future<void> activate(
    String code,
    String password,
    CancelToken cancel,
  ) async => calls.add('$code:${password.length}');
}

Widget _app(Widget child, List overrides) => ProviderScope(
  overrides: [...overrides.cast()],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  ),
);

class _FakeClaims implements PaymentClaimRepository {
  final rows = [
    PaymentClaim.fromJson({
      'id': 'c1',
      'amountPaise': 50000,
      'reference': '123456789012',
      'createdAt': '2026-11-16T05:00:00.000Z',
      'planName': 'Monthly',
      'member': {'name': 'Riya Shah', 'memberCode': 'ME001'},
    }),
  ];
  final calls = <String>[];
  @override
  Future<List<PaymentClaim>> pending(String gymId) async => List.of(rows);
  @override
  Future<void> confirm(String gymId, String claimId) async {
    calls.add('confirm:$claimId');
    rows.clear();
  }

  @override
  Future<void> reject(String gymId, String claimId, String reason) async {
    calls.add('reject:$claimId:$reason');
    rows.clear();
  }
}

class _FixedGym extends AdminGymController {
  @override
  AdminGymContext? build() => (userId: 'u1', gymId: gymId);
}

void main() {
  String date(DateTime day) => '${day.day}/${day.month}';

  test('membership headline tells the member what matters first', () {
    MemberHomeMembership m(Map<String, dynamic> changes) =>
        MemberHomeMembership.fromJson({
          ...homeJson()['membership'] as Map<String, dynamic>,
          ...changes,
        });
    expect(membershipHeadline(null, date).title, 'No membership yet');
    expect(membershipHeadline(m({}), date).title, '15 days left');
    expect(membershipHeadline(m({}), date).detail, 'Valid until 30/11.');
    final soon = membershipHeadline(
      m({'daysLeft': 3, 'expiringSoon': true}),
      date,
    );
    expect(soon.warn, isTrue);
    expect(soon.detail, contains('Renew soon'));
    expect(
      membershipHeadline(
        m({'daysLeft': 3, 'expiringSoon': true, 'renewedAhead': true}),
        date,
      ).warn,
      isFalse,
    );
    expect(
      membershipHeadline(
        m({'state': 'expired', 'daysLeft': 0, 'daysSinceExpiry': 5}),
        date,
      ).detail,
      startsWith('Ended 5 days ago'),
    );
    expect(
      membershipHeadline(m({'frozenUntil': '2026-11-20'}), date).title,
      'Frozen',
    );
    expect(
      membershipHeadline(m({'state': 'upcoming'}), date).title,
      'Starts 1/11',
    );
  });

  test('the code is found inside a pasted WhatsApp message', () {
    final message = activationMessage(
      firstName: 'Riya',
      gymName: 'Iron Gym',
      code: (code: code, expiresAt: DateTime(2026), email: 'r@x.com'),
      expiry: '19 Nov',
    );
    expect(message, contains('Activate with gym code'));
    expect(extractActivationCode(message), code);
    expect(extractActivationCode('  $code  '), code);
    expect(extractActivationCode('${code}x'), isNull);
    expect(extractActivationCode('short'), isNull);
  });

  testWidgets(
    'member home shows membership, dues, QR, visits, PT and payments',
    (tester) async {
      await tester.pumpWidget(
        _app(const MemberHomePage(), [
          memberGymIdProvider.overrideWithValue(gymId),
          memberGymsProvider.overrideWithValue(const []),
          memberHomeRepositoryProvider.overrideWithValue(_FakeHome(homeJson())),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hi Riya'), findsOneWidget);
      expect(find.text('15 days left'), findsOneWidget);
      expect(find.text('₹500.00 due'), findsOneWidget);
      expect(find.text('In today'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Weeks streak'), 200);
      expect(find.text('4'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('9 of 12 sessions left'),
        200,
      );
      await tester.scrollUntilVisible(find.text('₹1,000.00'), 200);
      expect(find.byTooltip('Receipt'), findsOneWidget);
    },
  );

  testWidgets('no membership: home still guides the member', (tester) async {
    await tester.pumpWidget(
      _app(const MemberHomePage(), [
        memberGymIdProvider.overrideWithValue(gymId),
        memberGymsProvider.overrideWithValue(const []),
        memberHomeRepositoryProvider.overrideWithValue(
          _FakeHome(homeJson(membership: null, balance: 0)),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No membership yet'), findsOneWidget);
    expect(find.textContaining('due'), findsNothing);
  });

  testWidgets('owner gives app access and gets a code to send', (tester) async {
    final access = _FakeAccess();
    final member = MemberProfile.fromJson({
      'id': memberId,
      'gymId': gymId,
      'memberCode': 'ME001',
      'firstName': 'Riya',
      'lastName': 'Shah',
      'phone': '9876543210',
      'status': 'active',
    });
    await tester.pumpWidget(
      _app(MemberAppAccessCard(gymId: gymId, member: member), [
        memberAccessRepositoryProvider.overrideWithValue(access),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give app access'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('member-access-email')),
      'riya@example.com',
    );
    await tester.tap(find.text('Create code'));
    await tester.pumpAndSettle();
    expect(access.calls, ['give:riya@example.com:Riya Shah']);
    expect(find.text('Send the code'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting for Riya'), findsOneWidget);
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(access.calls.last, 'new');
  });

  testWidgets('member activates with a pasted message and a new password', (
    tester,
  ) async {
    final repository = _FakeActivation();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activationRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(theme: AppTheme.dark, home: const ActivationPage()),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('activationCode')),
      'Code: $code',
    );
    await tester.enterText(
      find.byKey(const ValueKey('activationPassword')),
      'blue river morning',
    );
    await tester.enterText(
      find.byKey(const ValueKey('activationConfirm')),
      'blue river mornin',
    );
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(repository.calls, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('activationConfirm')),
      'blue river morning',
    );
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['$code:18']);
    expect(find.text('You are all set'), findsOneWidget);
  });

  testWidgets('member reports a UPI payment with its 12-digit ID', (
    tester,
  ) async {
    final repository = _FakeHome(homeJson());
    await tester.pumpWidget(
      _app(const MemberHomePage(), [
        memberGymIdProvider.overrideWithValue(gymId),
        memberGymsProvider.overrideWithValue(const []),
        memberHomeRepositoryProvider.overrideWithValue(repository),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pay ₹500.00 by UPI'), findsOneWidget);
    await tester.tap(find.text('Already paid by UPI? Report it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('upi-amount')), '600');
    await tester.enterText(
      find.byKey(const ValueKey('upi-reference')),
      '12345',
    );
    await tester.tap(find.text('Send to gym'));
    await tester.pumpAndSettle();
    expect(find.text('More than the ₹500.00 due'), findsOneWidget);
    expect(find.text('Enter all 12 digits'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('upi-amount')), '500');
    await tester.enterText(
      find.byKey(const ValueKey('upi-reference')),
      '123456789012',
    );
    await tester.tap(find.text('Send to gym'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['claim:50000:123456789012']);
    expect(
      find.textContaining('waiting for the gym to confirm'),
      findsOneWidget,
    );
    expect(find.text('Pay ₹500.00 by UPI'), findsNothing);
  });

  testWidgets('owner confirms or rejects reported UPI payments', (
    tester,
  ) async {
    final claims = _FakeClaims();
    await tester.pumpWidget(
      _app(const PaymentClaimsPage(), [
        adminGymProvider.overrideWith(_FixedGym.new),
        paymentClaimRepositoryProvider.overrideWithValue(claims),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Riya Shah'), findsOneWidget);
    expect(find.text('UPI transaction ID 123456789012'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('claim-reject-reason')),
      'Not received',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reject payment'));
    await tester.pumpAndSettle();
    expect(claims.calls, ['reject:c1:Not received']);
    expect(find.text('Nothing to confirm right now.'), findsOneWidget);
  });

  testWidgets('a rejected report tells the member why', (tester) async {
    final repository = _FakeHome(homeJson())
      ..claimRows = [
        {
          'amountPaise': 50000,
          'status': 'rejected',
          'rejectReason': 'Not received',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    await tester.pumpWidget(
      _app(const MemberHomePage(), [
        memberGymIdProvider.overrideWithValue(gymId),
        memberGymsProvider.overrideWithValue(const []),
        memberHomeRepositoryProvider.overrideWithValue(repository),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('UPI report was not accepted: Not received'),
      findsOneWidget,
    );
    final old = MemberClaim.fromJson({
      'amountPaise': 1,
      'status': 'rejected',
      'createdAt': '2026-01-01T00:00:00Z',
    });
    expect(recentRejection([old], DateTime(2026, 11, 16)), isNull);
  });
}
