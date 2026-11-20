import 'package:sqflite/sqflite.dart';

/// The single local database file (SPEC.md §5). Never leaves the phone.
abstract final class AppDatabase {
  static const _fileName = 'sagap.db';

  /// v1: app_settings. v2: homes, scans, samples, path_points.
  /// v3: rooms, priority_spots, homes.router_x/y (room sketch, M6).
  /// v4: channel_checks (aggregates only, M7).
  /// v5: hotspot_tests (M9).
  /// v6: rooms.outside, no_signal_spots (outside areas, out-of-range spots).
  static const schemaVersion = 6;

  static Future<Database> open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/$_fileName',
      version: schemaVersion,
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2(db);
        await _createV3(db);
        await _createV4(db);
        await _createV5(db);
        await _createV6(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
        if (oldVersion < 3) await _createV3(db);
        if (oldVersion < 4) await _createV4(db);
        if (oldVersion < 5) await _createV5(db);
        if (oldVersion < 6) await _createV6(db);
      },
    );
  }

  static Future<void> _createV1(Database db) => db.execute(
        'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );

  static Future<void> _createV2(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE homes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE scans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          home_id INTEGER NOT NULL REFERENCES homes(id),
          started_at INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          mode TEXT NOT NULL,
          sample_count INTEGER NOT NULL,
          median_dbm INTEGER,
          walked_m REAL,
          loop_error_m REAL
        )''')
      ..execute('''
        CREATE TABLE samples (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scan_id INTEGER NOT NULL REFERENCES scans(id),
          t_ms INTEGER NOT NULL,
          rssi_dbm INTEGER NOT NULL,
          freq_mhz INTEGER,
          x_m REAL,
          y_m REAL
        )''')
      ..execute('''
        CREATE TABLE path_points (
          scan_id INTEGER NOT NULL REFERENCES scans(id),
          segment INTEGER NOT NULL,
          seq INTEGER NOT NULL,
          x_m REAL NOT NULL,
          y_m REAL NOT NULL
        )''')
      ..execute('CREATE INDEX idx_scans_home ON scans(home_id)')
      ..execute('CREATE INDEX idx_samples_scan ON samples(scan_id)')
      ..execute('CREATE INDEX idx_path_scan ON path_points(scan_id)');
    await batch.commit(noResult: true);
  }

  static Future<void> _createV3(Database db) async {
    final batch = db.batch()
      ..execute('ALTER TABLE homes ADD COLUMN router_x REAL')
      ..execute('ALTER TABLE homes ADD COLUMN router_y REAL')
      ..execute('''
        CREATE TABLE rooms (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          home_id INTEGER NOT NULL REFERENCES homes(id),
          name TEXT NOT NULL,
          x REAL NOT NULL,
          y REAL NOT NULL,
          w REAL NOT NULL,
          h REAL NOT NULL
        )''')
      ..execute('''
        CREATE TABLE priority_spots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          home_id INTEGER NOT NULL REFERENCES homes(id),
          label TEXT NOT NULL,
          x REAL NOT NULL,
          y REAL NOT NULL
        )''')
      ..execute('CREATE INDEX idx_rooms_home ON rooms(home_id)')
      ..execute('CREATE INDEX idx_spots_home ON priority_spots(home_id)');
    await batch.commit(noResult: true);
  }

  /// Per-frequency neighbour counts as JSON; no network names or addresses.
  static Future<void> _createV4(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE channel_checks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scan_id INTEGER NOT NULL REFERENCES scans(id),
          json TEXT NOT NULL
        )''')
      ..execute('CREATE INDEX idx_checks_scan ON channel_checks(scan_id)');
    await batch.commit(noResult: true);
  }

  /// Candidate spots and per-spot medians as JSON.
  static Future<void> _createV5(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE hotspot_tests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          home_id INTEGER NOT NULL REFERENCES homes(id),
          started_at INTEGER NOT NULL,
          json TEXT NOT NULL
        )''')
      ..execute('CREATE INDEX idx_hotspot_home ON hotspot_tests(home_id)');
    await batch.commit(noResult: true);
  }

  /// Outside rooms (0 = home room) and out-of-range sketch spots.
  static Future<void> _createV6(Database db) async {
    final batch = db.batch()
      ..execute('ALTER TABLE rooms ADD COLUMN outside INTEGER NOT NULL DEFAULT 0')
      ..execute('''
        CREATE TABLE no_signal_spots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scan_id INTEGER NOT NULL REFERENCES scans(id),
          x_m REAL NOT NULL,
          y_m REAL NOT NULL
        )''')
      ..execute('CREATE INDEX idx_no_signal_scan ON no_signal_spots(scan_id)');
    await batch.commit(noResult: true);
  }
}
