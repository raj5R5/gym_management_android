import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Opt-in native persistence for recovery records. Unsupported platforms fail
/// closed; authentication continues using the plugin's ordinary methods.
class OnboardingSecureStorage extends FlutterSecureStorage {
  const OnboardingSecureStorage({this.recordPrefix = 'gym.onboarding.v1.'})
    : assert(
        recordPrefix == 'gym.onboarding.v1.' ||
            recordPrefix == 'gym.payment.v1.',
      ),
      super(
        aOptions: const AndroidOptions(resetOnError: false),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );

  final String recordPrefix;

  static const _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  Future<T?> _invoke<T>(String method, String key, [String? value]) {
    if (!key.startsWith(recordPrefix)) {
      throw ArgumentError('Only scoped recovery records are supported.');
    }
    final Map<String, String> options;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      options = aOptions.toMap();
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      options = iOptions.toMap();
    } else {
      throw UnsupportedError('Durable onboarding requires Android or iOS.');
    }
    return _channel.invokeMethod<T>(method, {
      'key': key,
      'value': ?value,
      'options': options,
    });
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _invoke<String>('readOnboarding', key);

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      throw ArgumentError('Use explicit acknowledgement to delete a record.');
    }
    // Android also returns the persisted value; await without discarding errors.
    await _invoke<String>('writeOnboarding', key, value);
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _invoke<String>('deleteOnboarding', key);
  }
}
