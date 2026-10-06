import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/app.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/features/auth/providers/auth_providers.dart';

import 'auth_fakes.dart';

Future<ProviderContainer> pumpGym(
  WidgetTester tester, {
  FakeAuthApi? api,
  FakeCredentialStorage? storage,
  AppConfig? config,
}) async {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config ?? AppConfig.fromValues()),
      authApiServiceProvider.overrideWithValue(api ?? FakeAuthApi()),
      credentialStorageProvider.overrideWithValue(
        storage ?? FakeCredentialStorage(),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const GymApp()),
  );
  await tester.pump();
  return container;
}

Future<void> enterLogin(
  WidgetTester tester, {
  String? email,
  String? password,
}) async {
  await tester.enterText(
    find.byType(TextFormField).at(0),
    email ?? 'person@example.invalid',
  );
  await tester.enterText(
    find.byType(TextFormField).at(1),
    password ?? syntheticCredential(),
  );
}
