import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/public_app_info.dart';
import 'app.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final publicInfo = PublicAppInfo.fromEnvironment();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        publicAppInfoProvider.overrideWithValue(publicInfo),
      ],
      child: const GymApp(),
    ),
  );
}
