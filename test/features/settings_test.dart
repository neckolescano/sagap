import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/domain/scan_session.dart';

import '../helpers/fakes.dart';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Homes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('permissions show status and open Android settings', (tester) async {
    final wifi = FakeWifiScanBridge();
    await pumpSagap(tester, ar: FakeArBridge(cameraAlreadyGranted: true), wifi: wifi);
    await openSettings(tester);

    await tester.scrollUntilVisible(find.text('Open Android settings'), 200);
    await tester.ensureVisible(find.text('Open Android settings'));
    await tester.pumpAndSettle();
    expect(find.text('Camera: Allowed'), findsOneWidget);
    expect(find.text('Location: Not allowed'), findsOneWidget);
    await tester.tap(find.text('Open Android settings'));
    await tester.pump();
    expect(wifi.settingsOpened, 1);
  });

  testWidgets('delete all data asks first, then clears every home', (tester) async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveScan(
      home,
      ScanRecord(
        startedAt: testNow,
        durationMs: 1000,
        mode: ScanMode.signalOnly,
        samples: const [StoredSample(tMs: 0, rssiDbm: -60)],
        path: const [],
      ),
    );
    await repo.createHome('Dorm', testNow);
    await pumpSagap(tester, repo: repo);
    await openSettings(tester);

    await tester.scrollUntilVisible(find.text('Delete all data'), 200);
    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.homesById, hasLength(2));

    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
    await tester.pumpAndSettle();
    expect(repo.homesById, isEmpty);
    expect(repo.scansById, isEmpty);
    expect(find.text('All data deleted'), findsOneWidget);
  });

  test('long-scan nudge after 15 minutes of recording', () {
    var s = const ScanSession.idle().start(testNow);
    // One reading per second; 900 s = 15 min.
    for (var i = 0; i <= 899; i++) {
      s = s.addReading(connectedReading(i * 1000, -60));
    }
    expect(s.recordedMs, 899000);
    expect(s.isLong, isFalse);
    s = s.addReading(connectedReading(900000, -60));
    expect(s.isLong, isTrue);
  });
}
