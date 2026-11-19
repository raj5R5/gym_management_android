import 'package:gym_management_app/features/gym_settings/gym_settings.dart';

/// In-memory settings; defaults to a fully configured gym.
class FakeGymSettingsRepository implements GymSettingsRepository {
  FakeGymSettingsRepository({GymSettings? settings})
    : settings =
          settings ??
          const GymSettings(
            timezone: 'Asia/Kolkata',
            timezoneConfigured: true,
            gstin: '27AAPFU0939F1ZV',
            address: GymAddress(line1: '12 MG Road', city: 'Pune'),
          );
  GymSettings settings;
  Object? failure;
  final updates = <Map<String, Object?>>[];

  @override
  Future<GymSettings> get(String gymId) async {
    if (failure != null) throw failure!;
    return settings;
  }

  @override
  Future<GymSettings> update(String gymId, Map<String, Object?> changes) async {
    updates.add(changes);
    if (failure != null) throw failure!;
    final address = changes.containsKey('address')
        ? (changes['address'] == null
              ? null
              : GymAddress.fromJson(
                  Map<String, dynamic>.from(changes['address']! as Map),
                ))
        : settings.address;
    return settings = GymSettings(
      timezone: (changes['timezone'] as String?) ?? settings.timezone,
      timezoneConfigured:
          changes['timezone'] != null || settings.timezoneConfigured,
      gstin: changes.containsKey('gstin')
          ? changes['gstin'] as String?
          : settings.gstin,
      address: address,
    );
  }
}
