class OwnerRegistrationSuccess {
  const OwnerRegistrationSuccess();
}

String? ownerFullNameError(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty || text.length > 120
      ? 'Enter your full name (1–120 characters).'
      : null;
}

String? ownerEmailError(String? value) {
  final text = (value ?? '').trim();
  return text.length <= 254 &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)
      ? null
      : 'Enter a valid email address.';
}

// Mirrors src/modules/auth/auth.validation.js. The backend remains authoritative.
String? ownerPasswordError(String? value) {
  final password = value ?? '';
  if (password.length < 15 || password.length > 128) {
    return 'Use a password with 15–128 characters.';
  }
  final comparison = password.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  const common = {
    'correcthorsebatterystaple',
    'thisisapassword',
    'iloveyou',
    'changeme',
    'letmein',
    'welcome',
    'admin',
    'gymmanagement',
  };
  if (password.trim().isEmpty ||
      RegExp(r'^(.{1,8})\1+$', unicode: true).hasMatch(password) ||
      common.contains(comparison) ||
      RegExp(
        r'^(?:p[a@]ssw[o0]rd|qwerty|letmein|welcome|changeme|administrator|1234567890|abcdefghijklmnopqrstuvwxyz)[0-9!@#$%^&*._-]*$',
        caseSensitive: false,
      ).hasMatch(password.trim())) {
    return 'Choose a less predictable password; avoid common or repeated patterns.';
  }
  return null;
}

String? ownerGymNameError(String? value) {
  final text = (value ?? '').trim();
  return text.length < 2 || text.length > 120
      ? 'Enter a gym name with 2–120 characters.'
      : null;
}

String? ownerGymPhoneError(String? value) {
  final phone = (value ?? '').trim();
  if (phone.isEmpty) return null;
  return phone.length >= 7 &&
          phone.length <= 25 &&
          RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) &&
          phone.replaceAll(RegExp(r'\D'), '').length >= 7
      ? null
      : 'Enter a valid gym phone number (7–25 characters).';
}

class OwnerRegistrationRequest {
  const OwnerRegistrationRequest({
    required this.ownerFullName,
    required this.email,
    required this.password,
    required this.gymName,
    this.gymContactPhone = '',
  });
  final String ownerFullName, email, password, gymName, gymContactPhone;
  Map<String, dynamic> toJson() {
    if ([
      ownerFullNameError(ownerFullName),
      ownerEmailError(email),
      ownerPasswordError(password),
      ownerGymNameError(gymName),
      ownerGymPhoneError(gymContactPhone),
    ].any((error) => error != null)) {
      throw const FormatException('Check the owner registration fields.');
    }
    return {
      'ownerFullName': ownerFullName.trim(),
      'email': email.trim(),
      'password': password,
      'gymName': gymName.trim(),
      if (gymContactPhone.trim().isNotEmpty)
        'gymContactPhone': gymContactPhone.trim(),
    };
  }

  @override
  String toString() => 'OwnerRegistrationRequest(private fields omitted)';
}
