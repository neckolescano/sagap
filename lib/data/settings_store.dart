import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Key-value app settings. Tests use an in-memory fake.
abstract interface class SettingsStore {
  Future<void> write(String key, String value);
}

/// Settings in the `app_settings` table of the local database.
class SqfliteSettingsStore implements SettingsStore {
  SqfliteSettingsStore(this._db);

  static const _table = 'app_settings';

  final Database _db;

  Future<Map<String, String>> readAll() async {
    final rows = await _db.query(_table);
    return {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  @override
  Future<void> write(String key, String value) => _db.insert(
        _table,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

abstract final class SettingsKeys {
  static const themeMode = 'theme_mode';
  static const onboardingDone = 'onboarding_done';
}

/// Overridden in `main()` with the opened store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw UnimplementedError('settingsStoreProvider must be overridden'),
);

/// Settings loaded at startup. Overridden in `main()`.
final initialSettingsProvider =
    Provider<Map<String, String>>((ref) => const {});
