import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/models/member_draft.dart';
import 'package:gym_management_app/features/members/models/onboarding_models.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';

void main() {
  test('member age gate handles exact birthday and leap-day boundary', () {
    expect(
      validateMemberBirthDate('2008-10-28', today: DateTime.utc(2026, 10, 27)),
      isNotNull,
    );
    expect(
      validateMemberBirthDate('2008-10-27', today: DateTime.utc(2026, 10, 27)),
      isNull,
    );
    expect(
      validateMemberBirthDate('2008-02-29', today: DateTime.utc(2026, 2, 28)),
      isNotNull,
    );
    expect(
      validateMemberBirthDate('2008-02-29', today: DateTime.utc(2026, 3, 1)),
      isNull,
    );
    expect(validateMemberBirthDate(''), isNull);
    expect(validateMemberBirthDate('invalid'), isNotNull);
    // Generic trainer/date validator retains its existing behavior.
    expect(validateBirthDate('2015-01-01'), isNull);
  });
  test(
    'new member draft cannot serialize a known minor; historical frozen receipt is preserved',
    () {
      final member = MemberDraft(
        memberCode: 'SYN01',
        firstName: 'Synthetic',
        lastName: 'Member',
        phone: '9876543210',
        dateOfBirth: CalendarDate.parse('2015-01-01'),
      );
      expect(() => member.toJson(editing: false), throwsFormatException);
      final frozen = jsonEncode({
        'member': {
          'memberCode': 'SYN01',
          'firstName': 'Synthetic',
          'lastName': 'Member',
          'phone': '9876543210',
          'dateOfBirth': '2015-01-01',
        },
      });
      final restored = OnboardingRequest.fromFrozenJson(frozen);
      expect(restored.frozenJson, frozen);
    },
  );
}
