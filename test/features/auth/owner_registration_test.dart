import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/auth/models/owner_registration.dart';
import 'auth_fakes.dart';

void main() {
  test(
    'request preserves password and sends only strict owner fields, omitting blank phone',
    () {
      final password = ' ${syntheticCredential()} ';
      final request = OwnerRegistrationRequest(
        ownerFullName: ' Alex River ',
        email: ' Owner@example.invalid ',
        password: password,
        gymName: ' Example Gym ',
        gymContactPhone: ' ',
      );
      final body = request.toJson();
      expect(body.keys.toSet(), {
        'ownerFullName',
        'email',
        'password',
        'gymName',
      });
      expect(body['ownerFullName'], 'Alex River');
      expect(body['email'], 'Owner@example.invalid');
      expect(body['gymName'], 'Example Gym');
      expect(body['password'] == password, isTrue);
      expect(request.toString().contains(password), isFalse);
    },
  );
  test(
    'client password policy only requires 1–128 characters, like the backend',
    () {
      expect(ownerPasswordError(''), 'Enter a password.');
      expect(ownerPasswordError(null), 'Enter a password.');
      expect(ownerPasswordError('x' * 129), 'Use at most 128 characters.');
      // No strength rules: short and common passwords are the owner's choice.
      for (final valid in ['1', '1234', 'password', 'abcabc', ' ', 'x' * 128]) {
        expect(ownerPasswordError(valid), isNull);
      }
    },
  );
  test('name, email, gym name and optional phone enforce the contract', () {
    expect(ownerFullNameError(''), isNotNull);
    expect(ownerFullNameError('x' * 121), isNotNull);
    expect(ownerEmailError('invalid'), isNotNull);
    expect(ownerEmailError('owner@example.invalid'), isNull);
    expect(ownerGymNameError('A'), isNotNull);
    expect(ownerGymNameError('Example Gym'), isNull);
    expect(ownerGymPhoneError(''), isNull);
    expect(ownerGymPhoneError('+91 9876543210'), isNull);
    expect(ownerGymPhoneError('abcdefg'), isNotNull);
    expect(ownerGymPhoneError('123456'), isNotNull);
    expect(ownerGymPhoneError('1' * 26), isNotNull);
  });
}
