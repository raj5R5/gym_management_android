import '../../admin_dashboard/models/dashboard_models.dart';
import 'member_models.dart';
import '../../../shared/validators/profile_validators.dart';
export '../../../shared/validators/profile_validators.dart';

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

String? validateMemberCode(String? value) => validateProfileCode(value);
