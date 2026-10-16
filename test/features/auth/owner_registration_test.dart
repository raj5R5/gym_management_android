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
    'client password policy matches backend lengths, blocklist, common-prefix and repeated-pattern rules',
    () {
      for (final invalid in [
        '',
        'short',
        'x' * 129,
        ' ' * 20,
        'abcd' * 8,
        'correcthorsebatterystaple',
        'Correct Horse Battery Staple',
        'password1234567890',
        'P@ssw0rd!12345678',
        'qwerty1234567890',
      ]) {
        expect(ownerPasswordError(invalid), isNotNull);
      }
      for (final valid in [
        syntheticCredential(),
        'River violet moon oak 47!',
        'abcdeFGHIJKLMN9',
        'a long sentence with a new line\nfinishes here',
      ]) {
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
