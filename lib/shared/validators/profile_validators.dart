import '../../features/admin_dashboard/models/dashboard_models.dart';

String? validateProfileCode(String? value) =>
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

/// A provisional form check; the backend uses the authorized gym calendar.
/// Blank DOB remains optional and must not be described as verified adulthood.
String? validateMemberBirthDate(String? value, {DateTime? today}) {
  final basic = validateBirthDate(value);
  if (basic != null || (value ?? '').trim().isEmpty) return basic;
  final birth = CalendarDate.parse(value!.trim()).value;
  final day = today ?? DateTime.now().toUtc();
  final age =
      day.year -
      birth.year -
      ((day.month < birth.month ||
              day.month == birth.month && day.day < birth.day)
          ? 1
          : 0);
  return age < 18
      ? 'Under-18 registration is unavailable until guardian authorization and verification are supported.'
      : null;
}
