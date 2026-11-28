enum AccountStatus { active, inactive, suspended }

enum AuthRole { admin, trainer, member }

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid authentication response.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid authentication response.');
  }
  return value;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.status,
    this.email,
    this.displayName,
    this.emailVerified = false,
    this.phone,
    this.phoneVerified = false,
    this.hasPassword = true,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final displayName = json['displayName'];
    if (displayName != null && displayName is! String) {
      throw const FormatException('Invalid account display name.');
    }
    for (final key in ['email', 'phone']) {
      final value = json[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        throw FormatException('Invalid account $key.');
      }
    }
    return AuthUser(
      id: _string(json, 'id'),
      email: json['email'] as String?,
      displayName: displayName as String?,
      status: AccountStatus.values.byName(_string(json, 'status')),
      emailVerified: json['emailVerified'] == true,
      phone: json['phone'] as String?,
      phoneVerified: json['phoneVerified'] == true,
      // Older servers did not say; every account then had a password.
      hasPassword: json['hasPassword'] != false,
    );
  }

  final String id;

  /// Optional: accounts made with a phone number may have no email.
  final String? email;

  /// The verified mobile, as +91 and 10 digits.
  final String? phone;
  final bool phoneVerified;

  /// False for accounts that sign in only with a phone code.
  final bool hasPassword;
  final String? displayName;
  final AccountStatus status;

  /// How to show who is signed in: email, else phone.
  String get contact => email ?? phone ?? '';

  /// The owner entered the code emailed to this address.
  final bool emailVerified;
}

/// Identity metadata returned by auth, not a gym feature or a client permission.
class AuthGymAccess {
  const AuthGymAccess({
    required this.id,
    required this.gymId,
    required this.role,
    required this.status,
    this.gymName,
  });

  factory AuthGymAccess.fromJson(Map<String, dynamic> json) => AuthGymAccess(
    id: _string(json, 'id'),
    gymId: _string(json, 'gymId'),
    gymName: json['gymName'] is String ? json['gymName'] as String : null,
    role: AuthRole.values.byName(_string(json, 'role')),
    status: AccountStatus.values.byName(_string(json, 'status')),
  );

  final String id;
  final String gymId;

  /// Shown when a person belongs to more than one gym.
  final String? gymName;
  final AuthRole role;
  final AccountStatus status;
}

class AuthIdentity {
  AuthIdentity({required this.user, required List<AuthGymAccess> gymAccess})
    : gymAccess = List.unmodifiable(gymAccess);

  factory AuthIdentity.fromJson(Map<String, dynamic> json) {
    final access = json['gymAccess'];
    if (access is! List) {
      throw const FormatException('Invalid account access information.');
    }
    return AuthIdentity(
      user: AuthUser.fromJson(_object(json['user'])),
      gymAccess: access
          .map((item) => AuthGymAccess.fromJson(_object(item)))
          .toList(),
    );
  }

  final AuthUser user;
  final List<AuthGymAccess> gymAccess;
}

/// Used only by the data layer. Never include credentials in UI session state.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final accessToken = _string(json, 'accessToken');
    final refreshToken = _string(json, 'refreshToken');
    final expiresIn = json['expiresIn'];
    final tokenType = _string(json, 'tokenType');
    if (accessToken.contains(RegExp(r'\s')) ||
        !validRefreshCredential(refreshToken) ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        tokenType != 'Bearer') {
      throw const FormatException('Invalid authentication credentials.');
    }
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      tokenType: tokenType,
    );
  }

  static bool validRefreshCredential(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;

  @override
  String toString() => 'AuthTokens(redacted)';
}

class LoginResponse {
  const LoginResponse({required this.identity, required this.tokens});
  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    identity: AuthIdentity.fromJson(json),
    tokens: AuthTokens.fromJson(json),
  );
  final AuthIdentity identity;
  final AuthTokens tokens;
}
