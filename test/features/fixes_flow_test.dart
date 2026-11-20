import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/channel_check.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

import '../helpers/fakes.dart';

void main() {
  const settle = Duration(milliseconds: 700);
  const crowded = ChannelCheck(
    ownFreqMhz: 2437,
    fresh: true,
    strongByFreq: {2437: 4, 2412: 1},
  );

  Future<void> startAndFinish(WidgetTester tester, FakeSignalSource source) async {
    source.emit(connectedReading(1000, -60));
    await tester.pump(settle);
    await tester.tap(find.text('Start scan'));
    // Not pumpAndSettle: the recording rings animate forever.
    await tester.pump();
    await tester.pump(settle);
  }

  group('location for the channel check', () {
    testWidgets('asks once with a reason; Allow requests the permission',
        (tester) async {
      final source = FakeSignalSource();
      final wifi = FakeWifiScanBridge();
      await pumpSagap(tester, source: source, wifi: wifi);
      await startAndFinish(tester, source);

      expect(find.text('Check nearby Wi-Fi channels?'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pump(settle);
      expect(wifi.locationRequests, 1);
      expect(find.text('Recording'), findsOneWidget);
    });

    testWidgets('Not now skips the request and is not asked again this launch',
        (tester) async {
      final source = FakeSignalSource();
      final wifi = FakeWifiScanBridge();
      await pumpSagap(tester, source: source, wifi: wifi);
      await startAndFinish(tester, source);
      await tester.tap(find.text('Not now'));
      await tester.pump(settle);
      expect(wifi.locationRequests, 0);

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start scan'));
      await tester.pump();
      await tester.pump(settle);
      expect(find.text('Check nearby Wi-Fi channels?'), findsNothing);
    });
  });

  testWidgets('channel checks at Start and Finish are saved with the scan',
      (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    final wifi = FakeWifiScanBridge(granted: true, result: crowded);
    await pumpSagap(tester, source: source, repo: repo, wifi: wifi);
    await startAndFinish(tester, source);
    source.emit(connectedReading(2000, -62));
    await tester.pump(settle);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(wifi.scans, scansPerSurvey);
    final (_, scan) = repo.scansById.values.single;
    expect(scan.channelChecks, hasLength(2));
    expect(scan.channelChecks.first.strongByFreq, {2437: 4, 2412: 1});
  });

  group('Fixes screen (S9)', () {
    /// Sketch: Sala (0–3 m) with the router, Bedroom (3–6 m) dead.
    Future<MemoryScanRepository> homeWithDeadBedroom({List<ChannelCheck> checks = const []}) async {
      final repo = MemoryScanRepository();
      final home = await repo.createHome('My home', testNow);
      await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 3, length: 1));
      await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Bedroom', x: 3, y: 0, width: 3, length: 1));
      await repo.setRouter(home, const FloorPoint(0, 0));
      const dbm = [-40, -50, -55, -58, -62, -70, -90, -90, -90, -90, -90, -90];
      await repo.saveScan(
        home,
        ScanRecord(
          startedAt: testNow,
          durationMs: 60000,
          mode: ScanMode.manual,
          samples: [
            for (final (i, v) in dbm.indexed)
              StoredSample(tMs: i, rssiDbm: v, xM: 0.25 + i * 0.5, yM: 0.25),
          ],
          path: const [],
          channelChecks: checks,
        ),
      );
      return repo;
    }

    Future<void> openFixes(WidgetTester tester) async {
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('See fixes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See fixes'));
      await tester.pumpAndSettle();
    }

    testWidgets('cards are ranked Free first, with an extender in Sala',
        (tester) async {
      await pumpSagap(tester, repo: await homeWithDeadBedroom(checks: const [crowded]));
      await openFixes(tester);

      expect(find.textContaining('Weak areas: Bedroom'), findsOneWidget);
      // Ranking order itself is covered by the AT17 unit test.
      await tester.scrollUntilVisible(
        find.text('Change the Wi-Fi channel in your router settings'),
        200,
      );
      expect(find.textContaining('channel 6 with 4 strong nearby networks'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Put a Wi-Fi extender here'), 200);
      expect(find.textContaining('In Sala'), findsOneWidget);
      await tester.tap(find.text('Put a Wi-Fi extender here'));
      await tester.pumpAndSettle();
      expect(find.text('Shown on the map above'), findsOneWidget);
    });

    testWidgets('no channel check → manual channel tip', (tester) async {
      await pumpSagap(tester, repo: await homeWithDeadBedroom());
      await openFixes(tester);
      await tester.scrollUntilVisible(find.text('Check your Wi-Fi channel'), 200);
      expect(find.text('Check your Wi-Fi channel'), findsOneWidget);
    });

    testWidgets('no weak areas → says so, no fix cards', (tester) async {
      final repo = MemoryScanRepository();
      final home = await repo.createHome('My home', testNow);
      await repo.saveScan(
        home,
        ScanRecord(
          startedAt: testNow,
          durationMs: 1000,
          mode: ScanMode.manual,
          samples: const [StoredSample(tMs: 0, rssiDbm: -50, xM: 0, yM: 0)],
          path: const [],
        ),
      );
      await pumpSagap(tester, repo: repo);
      await openFixes(tester);
      expect(find.textContaining('No dead zones found'), findsOneWidget);
      expect(find.text('Try the other Wi-Fi band'), findsNothing);
    });
  });
}
