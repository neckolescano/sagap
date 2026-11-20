import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/report/report_page.dart';

import '../helpers/fakes.dart';

ScanRecord sketchScan(DateTime at, List<StoredSample> samples) => ScanRecord(
      startedAt: at,
      durationMs: 60000,
      mode: ScanMode.manual,
      samples: samples,
      path: const [],
    );

StoredSample at(double x, double y, int rssi) =>
    StoredSample(tMs: 0, rssiDbm: rssi, xM: x, yM: y);

/// Home with a Sala and a Bedroom, and a weak walk then a better one.
Future<MemoryScanRepository> homeWithTwoWalks() async {
  final repo = MemoryScanRepository();
  final home = await repo.createHome('My home', testNow);
  await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 4, length: 3));
  await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Bedroom', x: 4, y: 0, width: 3, length: 3));
  await repo.addSpot(home, 'Desk', const FloorPoint(5.25, 1.25));
  await repo.saveScan(
    home,
    sketchScan(testNow.subtract(const Duration(days: 1)), [
      at(1.25, 1.25, -55), at(2.25, 2.25, -55), at(5.25, 1.25, -82), at(6.25, 2.25, -82),
    ]),
  );
  await repo.saveScan(
    home,
    sketchScan(testNow, [
      at(1.25, 1.25, -56), at(2.25, 2.25, -56), at(5.25, 1.25, -64), at(6.25, 2.25, -64),
    ]),
  );
  return repo;
}

Future<void> openCompare(WidgetTester tester) async {
  await tester.tap(find.text('Homes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My home'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Before and after'));
  await tester.pumpAndSettle();
}

/// Taps Share image and lets the real image encoding finish.
Future<void> tapShare(WidgetTester tester) async {
  await tester.tap(find.text('Share image'));
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one sketch scan: explains that two are needed', (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveScan(home, sketchScan(testNow, [at(1, 1, -60)]));
    await pumpSagap(tester, repo: repo);
    await openCompare(tester);
    expect(find.text('Two sketch scans needed'), findsOneWidget);
  });

  testWidgets('newest vs previous walk: rooms, spots and verdicts', (tester) async {
    await pumpSagap(tester, repo: await homeWithTwoWalks());
    await openCompare(tester);

    expect(find.text('19 Nov 2026, 14:05'), findsOneWidget, reason: 'before');
    expect(find.text('20 Nov 2026, 14:05'), findsOneWidget, reason: 'after');
    // Sala −55 → −56.
    expect(find.text('Excellent → Excellent · −1 dB · About the same'), findsOneWidget);
    // Bedroom −82 → −64, and the whole-home median: [−82 −82 −55 −55] → −82,
    // [−64 −64 −56 −56] → −64 (weaker middle value).
    expect(find.text('Dead zone → Good · +18 dB · Better'), findsNWidgets(2));
    // Desk snaps to (5.5, 1.5), a cell with no recorded spot: predicted.
    expect(find.textContaining('· Better · predicted'), findsOneWidget);
    expect(find.text('Typical signal'), findsOneWidget);
  });

  testWidgets('report from the comparison shares one PNG', (tester) async {
    final share = FakeShareBridge();
    await pumpSagap(tester, repo: await homeWithTwoWalks(), share: share);
    await openCompare(tester);
    await tester.scrollUntilVisible(find.text('Make a report'), 200);
    await tester.tap(find.text('Make a report'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportPage), findsOneWidget);
    expect(find.text('Wi-Fi report'), findsOneWidget);
    expect(find.textContaining('compared with 19 Nov 2026, 14:05'), findsOneWidget);

    await tapShare(tester);
    final (png, name) = share.shared.single;
    expect(name, 'sagap-report-20261120-1405.png');
    // PNG files start with these 4 bytes.
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('share failure is reported, not swallowed', (tester) async {
    final share = FakeShareBridge(
      error: PlatformException(code: 'no_app', message: 'No app on this phone can receive an image'),
    );
    await pumpSagap(tester, repo: await homeWithTwoWalks(), share: share);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Make a report'), 200);
    await tester.tap(find.text('Make a report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('compared with'), findsNothing);

    await tapShare(tester);
    expect(
      find.text("Couldn't share the report: No app on this phone can receive an image"),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share image')).onPressed,
        isNotNull);
  });

  test('report file name is dated to the minute', () {
    expect(reportFileName(DateTime(2026, 1, 5, 9, 7)), 'sagap-report-20260105-0907.png');
  });
}
