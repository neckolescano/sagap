import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/platform/ar_bridge.dart';

import '../helpers/fakes.dart';

void main() {
  const settle = Duration(milliseconds: 700);

  /// Records readings at -55, -66, -75 dBm (median -66 = Good) and taps Finish.
  Future<void> recordAndFinish(
    WidgetTester tester,
    FakeSignalSource source, {
    FakeArBridge? ar,
  }) async {
    source.emit(connectedReading(1000, -55));
    await tester.pump(settle);
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);
    ar?.emitPose(trackedPose(1950, 0, 0));
    ar?.emitPose(trackedPose(3100, 0, -2));
    source.emit(connectedReading(2000, -55));
    source.emit(connectedReading(3000, -66));
    source.emit(connectedReading(4000, -75));
    await tester.pump(settle);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
  }

  testWidgets('first save creates "My home" and stores the scan (AT8)',
      (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    await pumpSagap(tester, source: source, repo: repo);
    await recordAndFinish(tester, source);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save scan to'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'My home'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to My home'), findsOneWidget);
    expect(find.text('Scan finished'), findsNothing);
    expect(find.text('Start scan'), findsOneWidget);

    expect(repo.homesById.values.single.$1, 'My home');
    final (_, scan) = repo.scansById.values.single;
    expect(scan.mode, ScanMode.signalOnly);
    expect([for (final s in scan.samples) s.rssiDbm], [-55, -66, -75]);
    expect(scan.startedAt, testNow);
    expect(scan.durationMs, 2000);
  });

  testWidgets('second save defaults to the existing home', (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    final homeId = await repo.createHome('Dorm', testNow);
    await pumpSagap(tester, source: source, repo: repo);
    await recordAndFinish(tester, source);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Dorm'), findsOneWidget);
    expect(find.text('New home'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Saved to Dorm'), findsOneWidget);
    expect(repo.homesById, hasLength(1));
    expect(repo.scansById.values.single.$1, homeId);
  });

  testWidgets('cancelling the home dialog returns to the summary', (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    await pumpSagap(tester, source: source, repo: repo);
    await recordAndFinish(tester, source);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Scan finished'), findsOneWidget);
    expect(repo.scansById, isEmpty);
  });

  testWidgets('discard asks first; Cancel keeps the scan', (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    await pumpSagap(tester, source: source, repo: repo);
    await recordAndFinish(tester, source);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Scan finished'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Scan finished'), findsNothing);
    expect(repo.scansById, isEmpty);
  });

  testWidgets('AR scan saves readings paired with positions', (tester) async {
    final source = FakeSignalSource();
    final repo = MemoryScanRepository();
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await pumpSagap(tester, source: source, repo: repo, ar: ar);
    await recordAndFinish(tester, source, ar: ar);

    expect(find.text('2 of 3 readings have a position'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final (_, scan) = repo.scansById.values.single;
    expect(scan.mode, ScanMode.ar);
    expect([for (final s in scan.samples) (s.rssiDbm, s.xM, s.yM)], [
      (-55, 0.0, 0.0),
      (-66, 0.0, -2.0),
    ]);
    expect(scan.walkedM, closeTo(2, 1e-9));
  });

  testWidgets('Homes lists saved homes; detail lists scans; delete works',
      (tester) async {
    final repo = MemoryScanRepository();
    final homeId = await repo.createHome('My home', testNow);
    await repo.saveScan(
      homeId,
      ScanRecord(
        startedAt: testNow,
        durationMs: 65000,
        mode: ScanMode.signalOnly,
        samples: unpositionedSamples([
          connectedReading(1, -62),
          connectedReading(2, -64),
          connectedReading(3, -80),
        ]),
        path: const [],
      ),
    );
    await pumpSagap(tester, repo: repo);

    await tester.tap(find.text('Homes'));
    await tester.pumpAndSettle();
    expect(find.text('My home'), findsOneWidget);
    expect(find.text('1 scan · last 20 Nov 2026'), findsOneWidget);

    await tester.tap(find.text('My home'));
    await tester.pumpAndSettle();
    expect(find.text('20 Nov 2026, 14:05'), findsOneWidget);
    expect(find.text('Typically good\n1:05 · 3 readings · Signal only'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete scan'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this scan?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No scans'), findsOneWidget);
    expect(repo.scansById, isEmpty);

    await tester.tap(find.byTooltip('Home options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete home'));
    await tester.pumpAndSettle();
    expect(find.text('Delete My home?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.homesById, isEmpty);
    expect(find.text('No homes yet'), findsOneWidget);
  });

  testWidgets('rename a home', (tester) async {
    final repo = MemoryScanRepository();
    await repo.createHome('My home', testNow);
    await pumpSagap(tester, repo: repo);

    await tester.tap(find.text('Homes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Home options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lola house');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(repo.homesById.values.single.$1, 'Lola house');
    expect(find.text('Lola house'), findsOneWidget);
  });
}
