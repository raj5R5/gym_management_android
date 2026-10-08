import '../../admin_dashboard/models/dashboard_models.dart';
import 'member_models.dart';

/// Explicit allowlist: tenant, user linkage and branch assignment are never inputs.
class MemberDraft {
  MemberDraft({
    required this.memberCode,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.emergencyContact,
    this.status,
  });
  final String memberCode, firstName, lastName, phone;
  final CalendarDate? dateOfBirth;
  final String? gender;
  final MemberAddress? address;
  final EmergencyContact? emergencyContact;
  final MemberStatus? status;
  Map<String, dynamic> toJson({required bool editing}) {
    if (validateMemberCode(memberCode) != null ||
        validateName(firstName) != null ||
        validateName(lastName) != null ||
        validatePhone(phone) != null ||
        gender != null && !memberGenders.contains(gender) ||
        dateOfBirth != null &&
            dateOfBirth!.value.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Check the member information.');
    }
    return {
      if (!editing) 'memberCode': memberCode.trim().toUpperCase(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'phone': phone.trim(),
      if (editing || dateOfBirth != null)
        'dateOfBirth': dateOfBirth?.toString(),
      if (editing || gender != null) 'gender': gender,
      if (editing || address != null) 'address': address?.toJson(),
      if (editing || emergencyContact != null)
        'emergencyContact': emergencyContact?.toJson(),
      if (editing && status != null) 'status': status!.name,
    };
  }
}

String? validateMemberCode(String? value) =>
    RegExp(
      r'^[A-Z0-9][A-Z0-9_-]{1,31}$',
    ).hasMatch((value ?? '').trim().toUpperCase())
    ? null
    : 'Use 2–32 letters, digits, underscores or hyphens.';
String? validateName(String? value) =>
    (value ?? '').trim().isEmpty || value!.trim().length > 80
    ? 'Enter 1–80 characters.'
    : null;
String? validatePhone(String? value) {
  final phone = (value ?? '').trim();
  final digits = phone.replaceAll(RegExp(r'\D'), '').length;
  return phone.length <= 25 &&
          RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) &&
          digits >= 7 &&
          digits <= 15
      ? null
      : 'Enter a phone number with 7–15 digits.';
}

String? validateBirthDate(String? value) {
  if ((value ?? '').trim().isEmpty) return null;
  try {
    final date = CalendarDate.parse(value!.trim());
    if (date.value.isAfter(DateTime.now().toUtc())) {
      return 'Date of birth cannot be in the future.';
    }
    return null;
  } on FormatException {
    return 'Enter a valid date as YYYY-MM-DD.';
  }
}
