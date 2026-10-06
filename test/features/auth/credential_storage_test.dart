import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/storage/credential_storage.dart';

import 'auth_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'actual secure adapter isolates environment and API scopes and deletes only its key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const platformStorage = FlutterSecureStorage();
      const firstUrl = 'https://api.example.invalid/api/v1/';
      const secondUrl = 'https://other.example.invalid/api/v1/';
      final configs = [
        AppConfig.fromValues(apiBaseUrl: firstUrl),
        AppConfig.fromValues(
          environmentName: 'production',
          apiBaseUrl: firstUrl,
        ),
        AppConfig.fromValues(apiBaseUrl: secondUrl),
      ];
      final namespaces = configs.map(credentialStorageNamespace).toList();
      expect(namespaces.toSet().length, 3);
      expect(
        namespaces.first,
        'gym.auth.development.${Uri.encodeComponent(firstUrl)}',
      );
      final stores = namespaces
          .map(
            (namespace) => SecureCredentialStorage(
              storage: platformStorage,
              namespace: namespace,
            ),
          )
          .toList();
      final credentials = List.generate(3, (_) => syntheticCredential());
      for (var index = 0; index < stores.length; index++) {
        await stores[index].writeRefreshCredential(credentials[index]);
      }
      final keys = (await platformStorage.readAll()).keys.toSet();
      expect(keys, namespaces.map((namespace) => '$namespace.refresh').toSet());
      await stores.first.clearRefreshCredential();
      expect(await stores.first.readRefreshCredential(), isNull);
      for (var index = 1; index < stores.length; index++) {
        expect(
          await stores[index].readRefreshCredential() == credentials[index],
          isTrue,
        );
      }
      expect((await platformStorage.readAll()).length, 2);
    },
  );
}
