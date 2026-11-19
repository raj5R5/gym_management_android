import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';

class GymSettingsFailure implements Exception {
  const GymSettingsFailure(this.message);
  final String message;
  factory GymSettingsFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return GymSettingsFailure(switch (code) {
      'VALIDATION_ERROR' =>
        'Some details are not valid. Check the GST number and address.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
  @override
  String toString() => 'GymSettingsFailure: $message';
}

class GymAddress {
  const GymAddress({
    required this.line1,
    this.line2,
    required this.city,
    this.state,
    this.postalCode,
  });
  factory GymAddress.fromJson(Map<String, dynamic> json) => GymAddress(
    line1: json['line1'] as String,
    line2: json['line2'] as String?,
    city: json['city'] as String,
    state: json['state'] as String?,
    postalCode: json['postalCode'] as String?,
  );
  final String line1, city;
  final String? line2, state, postalCode;
  Map<String, String> toJson() => {
    'line1': line1,
    'line2': ?line2,
    'city': city,
    'state': ?state,
    'postalCode': ?postalCode,
  };
  String get singleLine => [
    line1,
    line2,
    city,
    state,
    postalCode,
  ].whereType<String>().where((part) => part.isNotEmpty).join(', ');
}

class GymSettings {
  const GymSettings({
    required this.timezone,
    required this.timezoneConfigured,
    this.gstin,
    this.address,
    this.upiId,
    this.upiPayeeName,
  });
  factory GymSettings.fromJson(Map<String, dynamic> json) {
    final address = json['address'];
    return GymSettings(
      timezone: json['timezone'] as String?,
      timezoneConfigured: json['timezoneConfigured'] == true,
      gstin: json['gstin'] as String?,
      address: address is Map<String, dynamic>
          ? GymAddress.fromJson(address)
          : null,
      upiId: json['upiId'] as String?,
      upiPayeeName: json['upiPayeeName'] as String?,
    );
  }
  final String? timezone, gstin, upiId, upiPayeeName;
  final bool timezoneConfigured;
  final GymAddress? address;
}

/// Common choices first; any valid IANA zone the server already holds is kept.
const commonGymTimezones = [
  ('Asia/Kolkata', 'India (IST)'),
  ('Asia/Dubai', 'UAE (GST)'),
  ('Asia/Kathmandu', 'Nepal'),
  ('Asia/Dhaka', 'Bangladesh'),
  ('Asia/Colombo', 'Sri Lanka'),
  ('Asia/Singapore', 'Singapore'),
  ('Europe/London', 'United Kingdom'),
  ('America/New_York', 'US Eastern'),
  ('UTC', 'UTC'),
];

/// UPI VPA such as `gymname@okaxis`; the server repeats this check.
final upiIdPattern = RegExp(r'^[a-z0-9._-]{2,256}@[a-z][a-z0-9.-]{1,63}$');

/// `upi://pay` link understood by GPay, PhonePe, Paytm and BHIM.
String upiPayUri({
  required String upiId,
  required String payeeName,
  required int amountPaise,
  required String note,
}) {
  final amount =
      '${amountPaise ~/ 100}.${(amountPaise % 100).toString().padLeft(2, '0')}';
  String encode(String value) => Uri.encodeComponent(value);
  return 'upi://pay?pa=${encode(upiId)}&pn=${encode(payeeName)}'
      '&am=$amount&cu=INR&tn=${encode(note)}';
}

/// Indian GSTIN format check; the server repeats this check.
final gstinPattern = RegExp(
  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
);

class GymSettingsRepository {
  GymSettingsRepository(this._client);
  final Dio _client;

  String _path(String gymId) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(gymId)) {
      throw const GymSettingsFailure('Invalid gym.');
    }
    return 'gyms/$gymId/settings';
  }

  Future<GymSettings> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> ||
          body['success'] != true ||
          body['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid settings envelope.');
      }
      return GymSettings.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw GymSettingsFailure.fromDio(error);
    } on GymSettingsFailure {
      rethrow;
    } catch (_) {
      throw const GymSettingsFailure(
        'The server returned unexpected gym settings.',
      );
    }
  }

  Future<GymSettings> get(String gymId) =>
      _send(() => _client.get<dynamic>(_path(gymId)));

  /// `null` values clear GSTIN or address; omitted keys stay unchanged.
  Future<GymSettings> update(String gymId, Map<String, Object?> changes) =>
      _send(() => _client.patch<dynamic>(_path(gymId), data: changes));
}

final gymSettingsRepositoryProvider = Provider<GymSettingsRepository>(
  (ref) => GymSettingsRepository(ref.watch(authenticatedApiClientProvider)),
);

final gymSettingsProvider = FutureProvider.autoDispose<GymSettings?>((ref) {
  final gym = ref.watch(adminGymProvider);
  if (gym == null) return null;
  return ref.watch(gymSettingsRepositoryProvider).get(gym.gymId);
}, retry: (_, _) => null);
