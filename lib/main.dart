import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/scan_repository.dart';
import 'data/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final settingsStore = SqfliteSettingsStore(db);
  final settings = await settingsStore.readAll();
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settingsStore),
        initialSettingsProvider.overrideWithValue(settings),
        scanRepositoryProvider.overrideWithValue(SqfliteScanRepository(db)),
      ],
      child: const SagapApp(),
    ),
  );
}
