import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_loss.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

import '../helpers/fakes.dart';

/// Hall 12 × 2 m, router at the left end, desk at the right end. Readings
/// follow P0 −40, n 4, so the far end is a dead zone.
Future<MemoryScanRepository> hallHome({int spots = 41, bool router = true}) async {
  final repo = MemoryScanRepository();
  final home = await repo.createHome('My home', testNow);
  await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Hall', x: 0, y: 0, width: 12, length: 2));
  if (router) await repo.setRouter(home, const FloorPoint(0, 1));
  await repo.addSpot(home, 'Desk', const FloorPoint(11.5, 1));
  const model = PathLossModel(p0: -40, exponent: 4, wallLossDb: [], walls: []);
  await repo.saveScan(
    home,
    ScanRecord(
      startedAt: testNow,
      durationMs: 60000,
      mode: ScanMode.manual,
      samples: [
        for (var i = 0; i < spots; i++)
          StoredSample(
            tMs: i,
            rssiDbm: model.predict(const FloorPoint(0, 1), FloorPoint(1 + i * 0.25, 1)).round(),
            xM: 1 + i * 0.25,
            yM: 1,
          ),
      ],
      path: const [],
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

Future<void> openWhatIf(WidgetTester tester) async {
  await openFixes(tester);
  final button = find.textContaining('Try moving the router');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('enough spots: Move the router card comes first (Free, Predicted)',
      (tester) async {
    await pumpSagap(tester, repo: await hallHome());
    await openFixes(tester);
    await tester.scrollUntilVisible(find.text('Move the router'), 200);
    expect(find.text('Predicted'), findsWidgets);
    expect(find.textContaining('Predicted: Desk'), findsOneWidget);
  });

  testWidgets('S10: Best spot moves the router and shows the predicted change',
      (tester) async {
    await pumpSagap(tester, repo: await hallHome());
    await openWhatIf(tester);

    expect(find.text('What if I move the router?'), findsOneWidget);
    expect(find.text('About the same'), findsOneWidget);
    expect(find.textContaining('Model fit: about ±'), findsOneWidget);

    await tester.tap(find.text('Best spot'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Desk Dead zone →'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('About the same'), findsOneWidget);
  });

  testWidgets('AT15-style gate: too few spots → explains, no simulator',
      (tester) async {
    await pumpSagap(tester, repo: await hallHome(spots: 5));
    await openWhatIf(tester);
    expect(find.text("Can't predict yet"), findsOneWidget);
    expect(find.textContaining('5 of ${PathLossSettings.minSamplesManual}'), findsOneWidget);
  });

  testWidgets('no router on the sketch → asks to mark it', (tester) async {
    await pumpSagap(tester, repo: await hallHome(router: false));
    await openWhatIf(tester);
    expect(find.text('Mark your router first'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
