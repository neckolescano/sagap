import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/map/heatmap_view.dart';

import '../helpers/fakes.dart';

void main() {
  ScanRecord record(ScanMode mode, List<StoredSample> samples) => ScanRecord(
        startedAt: testNow,
        durationMs: 60000,
        mode: mode,
        samples: samples,
        path: const [],
      );

  Future<void> openMap(WidgetTester tester) async {
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
  }

  testWidgets('no mappable scans: explains what to do', (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveScan(
      home,
      record(ScanMode.signalOnly, const [StoredSample(tMs: 1, rssiDbm: -60)]),
    );
    await pumpSagap(tester, repo: repo);
    await openMap(tester);

    expect(find.text('No map yet'), findsOneWidget);
    expect(find.byType(HeatmapView), findsNothing);
    expect(find.text('Faded = predicted'), findsOneWidget);
  });

  testWidgets('sketch scan: heatmap, then tap a spot to inspect (AT11, AT12)',
      (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveRoom(
      home,
      const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 4, length: 3),
    );
    await repo.saveScan(
      home,
      record(ScanMode.manual, const [
        StoredSample(tMs: 1, rssiDbm: -55, xM: 1, yM: 1),
        StoredSample(tMs: 2, rssiDbm: -75, xM: 3, yM: 2),
      ]),
    );
    await pumpSagap(tester, repo: repo);
    await openMap(tester);

    expect(find.text('My home · 20 Nov 2026, 14:05'), findsOneWidget);
    expect(find.byType(HeatmapView), findsOneWidget);
    expect(find.text('Tap the map to see a spot’s signal.'), findsOneWidget);
    expect(find.textContaining('Measured 2 · predicted'), findsOneWidget);

    // Map centre is (2, 1.5) m: equally far from both spots → IDW −65 = Good.
    await tester.tap(find.byType(HeatmapView));
    await tester.pumpAndSettle();
    expect(find.text('Good · −65 dBm · predicted'), findsOneWidget);
  });

  testWidgets('out-of-range spots are counted and reported on tap', (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveRoom(
      home,
      const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 4, length: 3),
    );
    await repo.saveScan(
      home,
      ScanRecord(
        startedAt: testNow,
        durationMs: 60000,
        mode: ScanMode.manual,
        samples: const [
          StoredSample(tMs: 1, rssiDbm: -55, xM: 1, yM: 1),
          StoredSample(tMs: 2, rssiDbm: -75, xM: 3, yM: 2),
        ],
        path: const [],
        noSignalSpots: const [FloorPoint(2, 1.5)],
      ),
    );
    await pumpSagap(tester, repo: repo);
    await openMap(tester);

    expect(find.textContaining('· 1 out of range'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Crossed ring = out of range'), 200);
    expect(find.text('Crossed ring = out of range'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(HeatmapView), -200);
    // Map centre (2, 1.5) m is the out-of-range spot.
    await tester.tap(find.byType(HeatmapView));
    await tester.pumpAndSettle();
    expect(find.text('Out of range · no Wi-Fi connection here'), findsOneWidget);
  });

  testWidgets('scan picker lists positioned scans only, newest first',
      (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('Dorm', testNow);
    await repo.saveScan(
      home,
      ScanRecord(
        startedAt: DateTime(2026, 11, 19, 9, 0),
        durationMs: 1000,
        mode: ScanMode.manual,
        samples: const [StoredSample(tMs: 1, rssiDbm: -60, xM: 0, yM: 0)],
        path: const [],
      ),
    );
    await repo.saveScan(
      home,
      record(ScanMode.signalOnly, const [StoredSample(tMs: 1, rssiDbm: -60)]),
    );
    await pumpSagap(tester, repo: repo);
    await openMap(tester);

    expect(find.text('Dorm · 19 Nov 2026, 09:00'), findsOneWidget);
    expect(find.text('Dorm · 20 Nov 2026, 14:05'), findsNothing,
        reason: 'the newer scan is signal-only');
  });
}
