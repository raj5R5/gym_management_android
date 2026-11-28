import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/features/account_security/account_security.dart';
import 'package:gym_management_app/features/account_security/account_security_page.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

class _Session extends SessionController {
  _Session(this.verified, {this.phoneOnly = false});
  final bool verified, phoneOnly;
  @override
  SessionState build() => SessionAuthenticated(
    AuthIdentity(
      user: phoneOnly
          ? const AuthUser(
              id: 'u1',
              status: AccountStatus.active,
              phone: '+919876543210',
              phoneVerified: true,
              hasPassword: false,
            )
          : AuthUser(
              id: 'u1',
              email: 'owner@example.com',
              status: AccountStatus.active,
              emailVerified: verified,
            ),
      gymAccess: const [],
    ),
  );
  @override
  Future<void> refreshSession() async {}
}

class _Repository extends AccountSecurityRepository {
  _Repository() : super(Dio());
  final calls = <String>[];
  bool wrongCurrent = false;
  @override
  Future<List<SignedInDevice>> devices() async => [
    for (final (id, current) in [('a', true), ('b', false), ('c', false)])
      SignedInDevice.fromJson({
        'id': id,
        'clientType': 'mobile',
        'current': current,
        'signedInAt': '2026-11-20T10:00:00Z',
        'lastUsedAt': '2026-11-27T10:00:00Z',
      }),
  ];
  @override
  Future<void> requestPhoneCode(String digits) async =>
      calls.add('phone:$digits');
  @override
  Future<void> confirmPhone(String digits, String code) async =>
      calls.add('confirm-phone:$digits:$code');
  @override
  Future<void> sendVerification() async => calls.add('send');
  @override
  Future<void> confirmVerification(String code) async =>
      calls.add('confirm:$code');
  @override
  Future<int> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (wrongCurrent) {
      throw const AccountSecurityFailure(
        'Your current password is not correct.',
      );
    }
    calls.add('password');
    return 2;
  }

  @override
  Future<int> signOutOthers() async {
    calls.add('others');
    return 2;
  }
}

void main() {
  Future<_Repository> pump(
    WidgetTester tester, {
    bool verified = false,
    bool phoneOnly = false,
  }) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSecurityRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(
            () => _Session(verified, phoneOnly: phoneOnly),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: AccountSecurityPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('an unverified email is verified with the emailed code', (
    tester,
  ) async {
    final repository = await pump(tester);
    expect(find.text('owner@example.com'), findsOneWidget);
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('We emailed you a 6-digit code'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('verification-code')),
      '123456',
    );
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['send', 'confirm:123456']);
    expect(find.text('Email verified.'), findsOneWidget);
  });

  testWidgets('a verified email says so', (tester) async {
    await pump(tester, verified: true);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Send verification code'), findsNothing);
  });

  testWidgets('changing the password checks both fields and reports devices', (
    tester,
  ) async {
    final repository = await pump(tester, verified: true);
    await tester.ensureVisible(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    const next = 'a-much-longer-new-passphrase-2026';
    await tester.enterText(
      find.byKey(const ValueKey('current-password')),
      'old',
    );
    await tester.enterText(find.byKey(const ValueKey('new-password')), next);
    await tester.enterText(
      find.byKey(const ValueKey('confirm-password')),
      'different',
    );
    await tester.ensureVisible(find.text('Save new password'));
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords must match.'), findsOneWidget);
    expect(repository.calls, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('confirm-password')),
      next,
    );
    repository.wrongCurrent = true;
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is not correct.'), findsOneWidget);

    repository.wrongCurrent = false;
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['password']);
    expect(
      find.text('Password changed. 2 other devices were signed out.'),
      findsOneWidget,
    );
  });

  testWidgets('other devices can be signed out after confirming', (
    tester,
  ) async {
    final repository = await pump(tester, verified: true);
    await tester.ensureVisible(find.text('Sign out 2 other devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out 2 other devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep signed in'));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    await tester.tap(find.text('Sign out 2 other devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out others'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['others']);
  });

  testWidgets(
    'a phone-only account shows its phone and no password to change',
    (tester) async {
      await pump(tester, phoneOnly: true);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.textContaining('No email on this account'), findsOneWidget);
      expect(find.text('Change password'), findsNothing);
    },
  );

  testWidgets('an email account adds a phone with an SMS code', (tester) async {
    final repository = await pump(tester, verified: true);
    await tester.tap(find.text('Add phone number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-phone')),
      '12345',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
    expect(repository.calls, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('account-phone')),
      '+91 98765 43210',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-phone-code')),
      '246810',
    );
    await tester.tap(find.text('Verify number'));
    await tester.pumpAndSettle();
    expect(repository.calls, [
      'phone:9876543210',
      'confirm-phone:9876543210:246810',
    ]);
  });
}
