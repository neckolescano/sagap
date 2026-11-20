import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/hotspot.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/sketch/sketch_canvas.dart';

import '../helpers/fakes.dart';

const settle = Duration(milliseconds: 300);

Future<(MemoryScanRepository, int)> homeWithSpots({bool spots = true}) async {
  final repo = MemoryScanRepository();
  final home = await repo.createHome('My home', testNow);
  await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 6, length: 4));
  if (spots) {
    await repo.addSpot(home, 'Desk', const FloorPoint(1, 1));
    await repo.addSpot(home, 'TV', const FloorPoint(5, 3));
  }
  return (repo, home);
}

Future<void> openHotspotTest(WidgetTester tester) async {
  await tester.tap(find.text('Homes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My home'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Hotspot test'));
  await tester.pumpAndSettle();
}

/// Records [dbm] five times at [spot].
Future<void> recordSpot(WidgetTester tester, FakeSignalSource source, String spot, int dbm, int t0) async {
  final tile = find.ancestor(of: find.text(spot), matching: find.byType(ListTile));
  await tester.tap(find.descendant(of: tile, matching: find.text('Record')));
  await tester.pump();
  for (var i = 0; i < manualReadingsPerSpot; i++) {
    source.emit(connectedReading(t0 + i * 1000, dbm));
    await tester.pump(settle);
  }
}

void main() {
  testWidgets('no priority spots → asks to add them', (tester) async {
    final (repo, _) = await homeWithSpots(spots: false);
    await pumpSagap(tester, repo: repo);
    await openHotspotTest(tester);
    expect(find.text('Add priority spots first'), findsOneWidget);
  });

  testWidgets('AT16 end to end: A then B, results, save', (tester) async {
    final (repo, home) = await homeWithSpots();
    final source = FakeSignalSource();
    await pumpSagap(tester, repo: repo, source: source);
    source.emit(connectedReading(1, -60));
    await tester.pump(settle);
    await openHotspotTest(tester);

    // Setup: two candidate spots.
    final canvas = tester.getCenter(find.byType(SketchCanvas));
    await tester.tapAt(canvas - const Offset(60, 0));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start test')).onPressed,
      isNull,
      reason: 'needs 2 spots',
    );
    await tester.tapAt(canvas + const Offset(60, 0));
    await tester.pump();
    expect(find.text('Spots: A, B'), findsOneWidget);
    await tester.tap(find.text('Start test'));
    await tester.pumpAndSettle();

    // Spot A: Record is disabled until connected to the hotspot.
    expect(find.text('Spot A (1 of 2)'), findsOneWidget);
    final record = find.widgetWithText(FilledButton, 'Record').first;
    expect(tester.widget<FilledButton>(record).onPressed, isNull);
    await tester.tap(find.text('This phone is connected to the laptop hotspot'));
    await tester.pump();
    await recordSpot(tester, source, 'Desk', -55, 1000);
    await recordSpot(tester, source, 'TV', -70, 10000);
    expect(find.text('Excellent · −55 dBm'), findsOneWidget);
    await tester.tap(find.text('Next: spot B'));
    await tester.pumpAndSettle();

    // Spot B.
    expect(find.text('Spot B (2 of 2)'), findsOneWidget);
    await tester.tap(find.text('This phone is connected to the laptop hotspot'));
    await tester.pump();
    await recordSpot(tester, source, 'Desk', -60, 20000);
    await recordSpot(tester, source, 'TV', -62, 30000);
    await tester.tap(find.text('See results'));
    await tester.pumpAndSettle();

    expect(
      find.text('Spot B gave the strongest signal at 1 of 2 priority spots '
          '(on average 1.5 dB better than A).'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Save result'), 200);
    await tester.tap(find.text('Save result'));
    await tester.pumpAndSettle();

    expect(find.text('Hotspot test saved'), findsOneWidget);
    final (_, saved) = repo.hotspotTests[home]!.single;
    expect(saved.readings, {
      'A': {'Desk': -55, 'TV': -70},
      'B': {'Desk': -60, 'TV': -62},
    });
  });

  testWidgets('saved result shows as a Measured (relative) card on Fixes',
      (tester) async {
    final (repo, home) = await homeWithSpots();
    await repo.saveScan(
      home,
      ScanRecord(
        startedAt: testNow,
        durationMs: 1000,
        mode: ScanMode.manual,
        samples: [
          for (var i = 0; i < 12; i++)
            StoredSample(tMs: i, rssiDbm: i < 6 ? -50 : -90, xM: 0.25 + i * 0.5, yM: 0.25),
        ],
        path: const [],
      ),
    );
    await repo.saveHotspotTest(
      home,
      testNow,
      const HotspotTest(
        candidates: [
          HotspotCandidate(label: 'A', point: FloorPoint(1, 1)),
          HotspotCandidate(label: 'B', point: FloorPoint(4, 2)),
        ],
        readings: {
          'A': {'Desk': -55, 'TV': -70},
          'B': {'Desk': -60, 'TV': -62},
        },
      ),
    );
    await pumpSagap(tester, repo: repo);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('See fixes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See fixes'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Router spot B tested best'), 200);
    expect(find.text('Measured (relative)'), findsOneWidget);
    expect(find.textContaining('Laptop hotspot test, 20 Nov 2026.'), findsOneWidget);
  });
}
