import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/shared/widgets/ambient_motion.dart';
import 'package:gym_management_app/features/auth/data/auth_repository.dart';
import 'package:gym_management_app/features/auth/data/phone_auth_repository.dart';
import 'package:gym_management_app/features/auth/models/auth_models.dart';
import 'package:gym_management_app/features/auth/models/session_state.dart';
import 'package:gym_management_app/features/auth/presentation/phone_sign_in_page.dart';
import 'package:gym_management_app/features/auth/providers/session_controller.dart';

import 'auth_fakes.dart';

class _Phone extends PhoneAuthRepository {
  _Phone() : super(Dio());
  final calls = <String>[];
  PhoneVerification result = PhoneSignedIn(
    LoginResponse(identity: syntheticIdentity(), tokens: syntheticTokens()),
  );
  PhoneAuthFailure? sendFailure;

  @override
  Future<PhoneCodeSent> requestCode(String digits) async {
    calls.add('send:$digits');
    if (sendFailure case final failure?) throw failure;
    return const PhoneCodeSent(resendAfter: Duration(seconds: 60));
  }

  @override
  Future<PhoneVerification> verify(String digits, String code) async {
    calls.add('verify:$digits:$code');
    if (code != '246810') {
      throw const PhoneAuthFailure('That code is not correct or has expired.');
    }
    return result;
  }

  @override
  Future<LoginResponse> registerOwner({
    required String signupToken,
    required String ownerFullName,
    required String gymName,
    String? email,
  }) async {
    calls.add('owner:$signupToken:$ownerFullName:$gymName:${email ?? ''}');
    return LoginResponse(
      identity: syntheticIdentity(),
      tokens: syntheticTokens(),
    );
  }
}

class _Session extends SessionController {
  final adopted = <LoginResponse>[];
  @override
  SessionState build() => const SessionUnauthenticated();
  @override
  Future<void> adoptSignIn(LoginResponse response) async =>
      adopted.add(response);
}

void main() {
  test('Indian mobiles are read however they are typed', () {
    for (final typed in [
      '9876543210',
      '+91 98765 43210',
      '098765-43210',
      '919876543210',
    ]) {
      expect(indianMobileDigits(typed), '9876543210', reason: typed);
    }
    for (final typed in [
      '12345',
      '5876543210',
      '+1 415 555 0100',
      '98765+43210+',
      '',
    ]) {
      expect(indianMobileDigits(typed), isNull, reason: typed);
    }
    expect(validateIndianMobile('98765'), 'Enter a 10-digit mobile number.');
  });

  test('the server explains waits and limits in plain words', () {
    PhoneAuthFailure from(String code, [int? wait]) => PhoneAuthFailure.fromDio(
      DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 429,
          data: {
            'success': false,
            'error': {
              'code': code,
              if (wait != null) 'details': {'retryAfterSeconds': wait},
            },
          },
        ),
      ),
    );
    expect(
      from('OTP_RESEND_TOO_SOON', 42).message,
      'Wait 42 seconds before asking for another code.',
    );
    expect(from('OTP_LIMIT_REACHED', 1800).message, contains('30 minutes'));
    expect(from('OTP_LIMIT_REACHED', 1800).retryAfterSeconds, 1800);
  });

  test('phone sign-in reads both server answers', () async {
    final adapter = CallbackAdapter((options) {
      final body = options.data as Map;
      return jsonResponse(
        success(
          body['code'] == '111111'
              ? {
                  'status': 'new_account',
                  'phone': '+919876543210',
                  'signupToken': 'a' * 43,
                  'expiresInSeconds': 900,
                }
              : {
                  'status': 'signed_in',
                  ...identityJson(),
                  ...tokenJson(syntheticTokens()),
                },
        ),
      );
    });
    final client = Dio(
      BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'),
    )..httpClientAdapter = adapter;
    final repository = PhoneAuthRepository(client);
    expect(
      await repository.verify('9876543210', '246810'),
      isA<PhoneSignedIn>(),
    );
    final created = await repository.verify('9876543210', '111111');
    expect(created, isA<PhoneNewAccount>());
    expect((created as PhoneNewAccount).signupToken, 'a' * 43);
    // Public calls never carry a stored credential.
    for (final request in adapter.requests) {
      expect(request.headers['Authorization'], isNull);
      expect(jsonDecode(jsonEncode(request.data))['phone'], '9876543210');
    }
  });

  test('a phone sign-in result becomes the stored session', () async {
    final storage = FakeCredentialStorage();
    final repository = AuthRepository(api: FakeAuthApi(), storage: storage);
    final tokens = syntheticTokens();
    await repository.adopt(
      LoginResponse(identity: syntheticIdentity(), tokens: tokens),
    );
    expect(repository.state, isA<SessionAuthenticated>());
    expect(storage.value, tokens.refreshToken);
    expect(repository.accessToken, tokens.accessToken);
    repository.dispose();
  });

  test('an account without email or password still reads', () {
    final user = AuthUser.fromJson({
      'id': 'u1',
      'email': null,
      'status': 'active',
      'phone': '+919876543210',
      'phoneVerified': true,
      'hasPassword': false,
    });
    expect(user.email, isNull);
    expect(user.contact, '+919876543210');
    expect(user.hasPassword, isFalse);
    // Older servers sent neither field: every account had a password then.
    expect(
      AuthUser.fromJson({
        'id': 'u1',
        'email': 'a@b.co',
        'status': 'active',
      }).hasPassword,
      isTrue,
    );
  });

  Future<(_Phone, _Session)> pump(WidgetTester tester) async {
    final phone = _Phone();
    final session = _Session();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          phoneAuthRepositoryProvider.overrideWithValue(phone),
          sessionControllerProvider.overrideWith(() => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          // The hero's ambient motion never settles; tests turn it off.
          builder: (context, child) =>
              AmbientMotionSettings(enabled: false, child: child!),
          home: const PhoneSignInPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (phone, session);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> throughCode(
    WidgetTester tester,
    SignInRole role, {
    String code = '246810',
  }) async {
    await tap(tester, find.byKey(ValueKey('role-${role.name}')));
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '98765 43210',
    );
    await tap(tester, find.text('Send code'));
    expect(find.text('Sent by SMS to +91 9876543210'), findsOneWidget);
    expect(find.text('Resend in 60s'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('otp-code')), code);
    await tap(tester, find.text('Verify'));
  }

  testWidgets('a known number signs straight in', (tester) async {
    final (phone, session) = await pump(tester);
    expect(find.text('Who is signing in?'), findsOneWidget);
    await throughCode(tester, SignInRole.member);
    expect(phone.calls, ['send:9876543210', 'verify:9876543210:246810']);
    expect(session.adopted, hasLength(1));
  });

  testWidgets('a wrong code says so and keeps the number', (tester) async {
    final (_, session) = await pump(tester);
    await throughCode(tester, SignInRole.owner, code: '111111');
    expect(
      find.text('That code is not correct or has expired.'),
      findsOneWidget,
    );
    expect(find.text('Sent by SMS to +91 9876543210'), findsOneWidget);
    expect(session.adopted, isEmpty);
  });

  testWidgets('a new owner names their gym; email is optional', (tester) async {
    final (phone, session) = await pump(tester);
    phone.result = const PhoneNewAccount(
      signupToken: 'ticket',
      phone: '+919876543210',
    );
    await throughCode(tester, SignInRole.owner);
    expect(find.text('Set up your gym.'), findsOneWidget);
    await tap(tester, find.text('Create my gym'));
    expect(find.text('Enter your name.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('owner-name')),
      'Ravi Kumar',
    );
    await tester.enterText(find.byKey(const ValueKey('gym-name')), 'Iron Den');
    await tester.enterText(
      find.byKey(const ValueKey('owner-email')),
      'not-an-email',
    );
    await tap(tester, find.text('Create my gym'));
    expect(
      find.text('Enter a valid email, or leave it empty.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('owner-email')), '');
    await tap(tester, find.text('Create my gym'));
    expect(phone.calls.last, 'owner:ticket:Ravi Kumar:Iron Den:');
    expect(session.adopted, hasLength(1));
  });

  testWidgets('a new member number is told to ask the gym', (tester) async {
    final (phone, session) = await pump(tester);
    phone.result = const PhoneNewAccount(
      signupToken: 'ticket',
      phone: '+919876543210',
    );
    await throughCode(tester, SignInRole.member);
    expect(find.text('Not linked yet.'), findsOneWidget);
    expect(find.textContaining('Ask your gym to add you'), findsOneWidget);
    expect(phone.calls.where((call) => call.startsWith('owner:')), isEmpty);
    expect(session.adopted, isEmpty);
  });

  testWidgets('a bad number is caught before any SMS, and send errors show', (
    tester,
  ) async {
    final (phone, _) = await pump(tester);
    await tap(tester, find.byKey(const ValueKey('role-trainer')));
    await tester.enterText(find.byKey(const ValueKey('phone-number')), '12345');
    await tap(tester, find.text('Send code'));
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
    expect(phone.calls, isEmpty);
    phone.sendFailure = const PhoneAuthFailure(
      'Wait 30 seconds before asking for another code.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '9876543210',
    );
    await tap(tester, find.text('Send code'));
    expect(
      find.text('Wait 30 seconds before asking for another code.'),
      findsOneWidget,
    );
  });
}
