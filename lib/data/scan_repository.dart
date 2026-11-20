import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/channel_check.dart';
import '../domain/home_layout.dart';
import '../domain/hotspot.dart';
import '../domain/path_track.dart';
import '../domain/scan_record.dart';

/// Homes and scans on the phone (SPEC.md §5). Tests use an in-memory fake.
abstract interface class ScanRepository {
  Future<List<HomeSummary>> homes();
  Future<int> createHome(String name, DateTime createdAt);
  Future<void> renameHome(int homeId, String name);

  /// Deletes the home with all its scans, samples and paths.
  Future<void> deleteHome(int homeId);

  Future<int> saveScan(int homeId, ScanRecord scan);
  Future<List<ScanSummary>> scansForHome(int homeId);
  Future<List<StoredSample>> samplesForScan(int scanId);
  Future<List<ChannelCheck>> channelChecksForScan(int scanId);

  /// Out-of-range sketch spots of a scan (may be empty).
  Future<List<FloorPoint>> noSignalSpotsForScan(int scanId);
  Future<void> deleteScan(int scanId);

  // Room sketch (M6).
  Future<HomeLayout> layoutForHome(int homeId);

  /// Inserts the room when its id is negative, otherwise updates it.
  /// Returns the stored id.
  Future<int> saveRoom(int homeId, SketchRoom room);
  Future<void> deleteRoom(int roomId);
  Future<void> setRouter(int homeId, FloorPoint? router);
  Future<int> addSpot(int homeId, String label, FloorPoint point);
  Future<void> deleteSpot(int spotId);

  // Laptop hotspot test (M9).
  Future<void> saveHotspotTest(int homeId, DateTime at, HotspotTest test);

  /// Newest hotspot test for a home, or null.
  Future<(DateTime, HotspotTest)?> latestHotspotTest(int homeId);
}

class SqfliteScanRepository implements ScanRepository {
  SqfliteScanRepository(this._db);

  final Database _db;

  static String _modeName(ScanMode mode) => switch (mode) {
        ScanMode.ar => 'ar',
        ScanMode.signalOnly => 'signal',
        ScanMode.manual => 'manual',
      };

  static ScanMode _modeFrom(Object? name) => switch (name) {
        'ar' => ScanMode.ar,
        'signal' => ScanMode.signalOnly,
        'manual' => ScanMode.manual,
        _ => throw FormatException('Unknown scan mode in database', name),
      };

  @override
  Future<HomeLayout> layoutForHome(int homeId) async {
    final homeRows = await _db.query(
      'homes',
      columns: ['router_x', 'router_y'],
      where: 'id = ?',
      whereArgs: [homeId],
    );
    if (homeRows.isEmpty) throw StateError('Home $homeId not found');
    final rx = homeRows.single['router_x'] as double?;
    final ry = homeRows.single['router_y'] as double?;
    final rooms = await _db.query('rooms', where: 'home_id = ?', whereArgs: [homeId], orderBy: 'id');
    final spots = await _db.query('priority_spots', where: 'home_id = ?', whereArgs: [homeId], orderBy: 'id');
    return HomeLayout(
      router: rx == null || ry == null ? null : FloorPoint(rx, ry),
      rooms: [
        for (final r in rooms)
          SketchRoom(
            id: r['id']! as int,
            name: r['name']! as String,
            x: r['x']! as double,
            y: r['y']! as double,
            width: r['w']! as double,
            length: r['h']! as double,
            outside: r['outside'] == 1,
          ),
      ],
      spots: [
        for (final s in spots)
          PrioritySpot(
            id: s['id']! as int,
            label: s['label']! as String,
            point: FloorPoint(s['x']! as double, s['y']! as double),
          ),
      ],
    );
  }

  @override
  Future<int> saveRoom(int homeId, SketchRoom room) async {
    final values = {
      'home_id': homeId,
      'name': room.name,
      'x': room.x,
      'y': room.y,
      'w': room.width,
      'h': room.length,
      'outside': room.outside ? 1 : 0,
    };
    if (room.id < 0) return _db.insert('rooms', values);
    final changed = await _db.update('rooms', values, where: 'id = ?', whereArgs: [room.id]);
    if (changed != 1) throw StateError('Room ${room.id} not found');
    return room.id;
  }

  @override
  Future<void> deleteRoom(int roomId) =>
      _db.delete('rooms', where: 'id = ?', whereArgs: [roomId]);

  @override
  Future<void> setRouter(int homeId, FloorPoint? router) async {
    final changed = await _db.update(
      'homes',
      {'router_x': router?.x, 'router_y': router?.y},
      where: 'id = ?',
      whereArgs: [homeId],
    );
    if (changed != 1) throw StateError('Home $homeId not found');
  }

  @override
  Future<int> addSpot(int homeId, String label, FloorPoint point) =>
      _db.insert('priority_spots', {
        'home_id': homeId,
        'label': label,
        'x': point.x,
        'y': point.y,
      });

  @override
  Future<void> deleteSpot(int spotId) =>
      _db.delete('priority_spots', where: 'id = ?', whereArgs: [spotId]);

  @override
  Future<void> saveHotspotTest(int homeId, DateTime at, HotspotTest test) =>
      _db.insert('hotspot_tests', {
        'home_id': homeId,
        'started_at': at.millisecondsSinceEpoch,
        'json': jsonEncode(test.toJson()),
      });

  @override
  Future<(DateTime, HotspotTest)?> latestHotspotTest(int homeId) async {
    final rows = await _db.query(
      'hotspot_tests',
      where: 'home_id = ?',
      whereArgs: [homeId],
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return (
      DateTime.fromMillisecondsSinceEpoch(r['started_at']! as int),
      HotspotTest.fromJson(jsonDecode(r['json']! as String) as Map<String, Object?>),
    );
  }

  @override
  Future<List<HomeSummary>> homes() async {
    final rows = await _db.rawQuery('''
      SELECT h.id, h.name, h.created_at,
             COUNT(s.id) AS scan_count, MAX(s.started_at) AS last_scan_at
      FROM homes h LEFT JOIN scans s ON s.home_id = h.id
      GROUP BY h.id
      ORDER BY COALESCE(MAX(s.started_at), h.created_at) DESC''');
    return [
      for (final r in rows)
        HomeSummary(
          id: r['id']! as int,
          name: r['name']! as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
          scanCount: r['scan_count']! as int,
          lastScanAt: switch (r['last_scan_at']) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
            _ => null,
          },
        ),
    ];
  }

  @override
  Future<int> createHome(String name, DateTime createdAt) => _db.insert('homes', {
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      });

  @override
  Future<void> renameHome(int homeId, String name) async {
    final changed = await _db.update(
      'homes',
      {'name': name},
      where: 'id = ?',
      whereArgs: [homeId],
    );
    if (changed != 1) throw StateError('Home $homeId not found');
  }

  @override
  Future<void> deleteHome(int homeId) => _db.transaction((txn) async {
        const scanIds = 'SELECT id FROM scans WHERE home_id = ?';
        await txn.delete('samples', where: 'scan_id IN ($scanIds)', whereArgs: [homeId]);
        await txn.delete('channel_checks', where: 'scan_id IN ($scanIds)', whereArgs: [homeId]);
        await txn.delete('no_signal_spots', where: 'scan_id IN ($scanIds)', whereArgs: [homeId]);
        await txn.delete('path_points', where: 'scan_id IN ($scanIds)', whereArgs: [homeId]);
        await txn.delete('scans', where: 'home_id = ?', whereArgs: [homeId]);
        await txn.delete('rooms', where: 'home_id = ?', whereArgs: [homeId]);
        await txn.delete('priority_spots', where: 'home_id = ?', whereArgs: [homeId]);
        await txn.delete('hotspot_tests', where: 'home_id = ?', whereArgs: [homeId]);
        await txn.delete('homes', where: 'id = ?', whereArgs: [homeId]);
      });

  @override
  Future<int> saveScan(int homeId, ScanRecord scan) => _db.transaction((txn) async {
        final scanId = await txn.insert('scans', {
          'home_id': homeId,
          'started_at': scan.startedAt.millisecondsSinceEpoch,
          'duration_ms': scan.durationMs,
          'mode': _modeName(scan.mode),
          'sample_count': scan.samples.length,
          'median_dbm': scan.medianDbm,
          'walked_m': scan.walkedM,
          'loop_error_m': scan.loopErrorM,
        });
        final batch = txn.batch();
        for (final s in scan.samples) {
          batch.insert('samples', {
            'scan_id': scanId,
            't_ms': s.tMs,
            'rssi_dbm': s.rssiDbm,
            'freq_mhz': s.freqMhz,
            'x_m': s.xM,
            'y_m': s.yM,
          });
        }
        for (final (segment, points) in scan.path.indexed) {
          for (final (seq, p) in points.indexed) {
            batch.insert('path_points', {
              'scan_id': scanId,
              'segment': segment,
              'seq': seq,
              'x_m': p.x,
              'y_m': p.y,
            });
          }
        }
        for (final check in scan.channelChecks) {
          batch.insert('channel_checks', {
            'scan_id': scanId,
            'json': jsonEncode(check.toJson()),
          });
        }
        for (final p in scan.noSignalSpots) {
          batch.insert('no_signal_spots', {'scan_id': scanId, 'x_m': p.x, 'y_m': p.y});
        }
        await batch.commit(noResult: true);
        return scanId;
      });

  @override
  Future<List<ChannelCheck>> channelChecksForScan(int scanId) async {
    final rows = await _db.query(
      'channel_checks',
      where: 'scan_id = ?',
      whereArgs: [scanId],
      orderBy: 'id',
    );
    return [
      for (final r in rows)
        ChannelCheck.fromJson(jsonDecode(r['json']! as String) as Map<String, Object?>),
    ];
  }

  @override
  Future<List<FloorPoint>> noSignalSpotsForScan(int scanId) async {
    final rows = await _db.query(
      'no_signal_spots',
      where: 'scan_id = ?',
      whereArgs: [scanId],
      orderBy: 'id',
    );
    return [for (final r in rows) FloorPoint(r['x_m']! as double, r['y_m']! as double)];
  }

  @override
  Future<List<ScanSummary>> scansForHome(int homeId) async {
    final rows = await _db.query(
      'scans',
      where: 'home_id = ?',
      whereArgs: [homeId],
      orderBy: 'started_at DESC',
    );
    return [
      for (final r in rows)
        ScanSummary(
          id: r['id']! as int,
          homeId: r['home_id']! as int,
          startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at']! as int),
          durationMs: r['duration_ms']! as int,
          mode: _modeFrom(r['mode']),
          sampleCount: r['sample_count']! as int,
          medianDbm: r['median_dbm'] as int?,
          walkedM: r['walked_m'] as double?,
          loopErrorM: r['loop_error_m'] as double?,
        ),
    ];
  }

  @override
  Future<List<StoredSample>> samplesForScan(int scanId) async {
    final rows = await _db.query(
      'samples',
      where: 'scan_id = ?',
      whereArgs: [scanId],
      orderBy: 't_ms',
    );
    return [
      for (final r in rows)
        StoredSample(
          tMs: r['t_ms']! as int,
          rssiDbm: r['rssi_dbm']! as int,
          freqMhz: r['freq_mhz'] as int?,
          xM: r['x_m'] as double?,
          yM: r['y_m'] as double?,
        ),
    ];
  }

  @override
  Future<void> deleteScan(int scanId) => _db.transaction((txn) async {
        await txn.delete('samples', where: 'scan_id = ?', whereArgs: [scanId]);
        await txn.delete('channel_checks', where: 'scan_id = ?', whereArgs: [scanId]);
        await txn.delete('no_signal_spots', where: 'scan_id = ?', whereArgs: [scanId]);
        await txn.delete('path_points', where: 'scan_id = ?', whereArgs: [scanId]);
        await txn.delete('scans', where: 'id = ?', whereArgs: [scanId]);
      });
}

/// Overridden in `main()` with the opened repository.
final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) => throw UnimplementedError('scanRepositoryProvider must be overridden'),
);

/// Saved homes, newest activity first. Invalidate after changes.
final homesProvider = FutureProvider<List<HomeSummary>>(
  (ref) => ref.watch(scanRepositoryProvider).homes(),
  retry: (_, _) => null,
);

/// Saved scans for one home, newest first. Invalidate after changes.
final scansForHomeProvider = FutureProvider.family<List<ScanSummary>, int>(
  (ref, homeId) => ref.watch(scanRepositoryProvider).scansForHome(homeId),
  retry: (_, _) => null,
);

/// Wall clock, injectable for tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Builds the record to save from a finished session.
ScanRecord buildScanRecord({
  required DateTime startedAt,
  required int durationMs,
  required ScanMode mode,
  required List<StoredSample> samples,
  PathTrack? track,
  List<ChannelCheck> channelChecks = const [],
  List<FloorPoint> noSignalSpots = const [],
}) =>
    ScanRecord(
      channelChecks: channelChecks,
      noSignalSpots: noSignalSpots,
      startedAt: startedAt,
      durationMs: durationMs,
      mode: mode,
      samples: samples,
      path: track?.segments ?? const [],
      walkedM: track?.walkedM,
      loopErrorM: track == null || track.start == null ? null : track.distanceFromStartM,
    );
