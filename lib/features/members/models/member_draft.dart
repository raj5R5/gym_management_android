import '../../admin_dashboard/models/dashboard_models.dart';
import 'member_models.dart';
import '../../../shared/validators/profile_validators.dart';
export '../../../shared/validators/profile_validators.dart';

/// Explicit allowlist: tenant and user linkage are never inputs.
class MemberDraft {
  MemberDraft({
    this.memberCode = '',
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
        validateMemberBirthDate(dateOfBirth?.toString()) != null) {
      throw const FormatException('Check the member information.');
    }
    return {
      // Left out when empty: the server numbers the member (M0001, …).
      if (!editing && memberCode.trim().isNotEmpty)
        'memberCode': memberCode.trim().toUpperCase(),
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

/// Member codes are optional labels and may repeat; the phone identifies a member.
String? validateMemberCode(String? value) =>
    (value ?? '').trim().isEmpty ? null : validateProfileCode(value);

/// The key that makes a member's phone unique in a gym: digits only, and the
/// last 10 digits when longer. Mirrors the backend's member.phone.js.
String memberPhoneKey(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}
