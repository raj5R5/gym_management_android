import '../../../shared/validators/profile_validators.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
import 'trainer_models.dart';

class TrainerDraft {
  TrainerDraft({
    required this.trainerCode,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.status,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.specializations,
  });
  final String trainerCode, firstName, lastName, phone;
  final TrainerStatus? status;
  final CalendarDate? dateOfBirth;
  final String? gender;
  final ProfileAddress? address;
  final List<String>? specializations;
  Map<String, dynamic> toJson({required bool editing}) {
    if (validateProfileCode(trainerCode) != null ||
        validateName(firstName) != null ||
        validateName(lastName) != null ||
        validatePhone(phone) != null ||
        gender != null && !trainerGenders.contains(gender) ||
        dateOfBirth != null &&
            dateOfBirth!.value.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Check the trainer information.');
    }
    parseSpecializations(specializations);
    return {
      if (!editing) 'trainerCode': trainerCode.trim().toUpperCase(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'phone': phone.trim(),
      if (status != null) 'status': status!.name,
      if (editing || dateOfBirth != null)
        'dateOfBirth': dateOfBirth?.toString(),
      if (editing || gender != null) 'gender': gender,
      if (editing || address != null) 'address': address?.toJson(),
      if (editing || specializations != null)
        'specializations': specializations
            ?.map((value) => value.trim())
            .toList(),
    };
  }
}

/// One entry per line avoids treating commas within a specialization as separators.
String? validateSpecializations(String? value) {
  try {
    parseSpecializations(specializationsFromInput(value ?? ''));
    return null;
  } on FormatException {
    return 'Use up to 10 distinct specializations, 1–80 characters each.';
  }
}

List<String>? specializationsFromInput(String value) {
  if (value.trim().isEmpty) return null;
  return value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
