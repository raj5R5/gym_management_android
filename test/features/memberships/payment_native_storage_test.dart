import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/data/onboarding_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform payment adapter uses durable native recovery methods',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <MethodCall>[];
        String? disk;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              expect(call.arguments['key'], 'gym.payment.v1.synthetic.pending');
              if (call.method == 'writeOnboarding') {
                disk = call.arguments['value'] as String;
              }
              if (call.method == 'deleteOnboarding') disk = null;
              return disk;
            });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        const storage = OnboardingSecureStorage(
          recordPrefix: 'gym.payment.v1.',
        );
        await storage.write(
          key: 'gym.payment.v1.synthetic.pending',
          value: 'frozen',
        );
        expect(
          await storage.read(key: 'gym.payment.v1.synthetic.pending'),
          'frozen',
        );
        await storage.delete(key: 'gym.payment.v1.synthetic.pending');
        expect(calls.map((call) => call.method), [
          'writeOnboarding',
          'readOnboarding',
          'deleteOnboarding',
        ]);
        expect(() => storage.read(key: 'auth.refresh'), throwsArgumentError);
        await expectLater(
          storage.write(
            key: 'gym.onboarding.v1.synthetic.pending',
            value: 'other',
          ),
          throwsArgumentError,
        );
        expect(calls, hasLength(3));
      },
    );
  }
}
