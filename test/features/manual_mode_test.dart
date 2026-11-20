import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/sketch/sketch_canvas.dart';

import '../helpers/fakes.dart';

void main() {
  const settle = Duration(milliseconds: 700);

  /// Scan tab → "Map with a room sketch" → new home "My home" → editor.
  Future<void> openEditorForNewHome(WidgetTester tester) async {
    await tester.tap(find.text('Map with a room sketch'));
    await tester.pumpAndSettle();
    expect(find.text('Sketch which home?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Sketch your rooms'), findsOneWidget);
  }

  Future<void> addRoom(WidgetTester tester, {String? name, String? width}) async {
    await tester.tap(find.text('Add room'));
    await tester.pumpAndSettle();
    if (name != null) {
      await tester.enterText(find.widgetWithText(TextField, 'Room name'), name);
    }
    if (width != null) {
      await tester.enterText(find.widgetWithText(TextField, 'Width (m)'), width);
    }
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('sketch a home: add room, router and spot; Done enters manual mode',
      (tester) async {
    final repo = MemoryScanRepository();
    await pumpSagap(tester, repo: repo);
    await openEditorForNewHome(tester);

    expect(find.text('Add each room as a rectangle.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Done')).onPressed,
      isNull,
    );

    await addRoom(tester, name: 'Sala');
    final homeId = repo.homesById.keys.single;
    final room = repo.layouts[homeId]!.rooms.single;
    expect((room.name, room.width, room.length), ('Sala', 3.0, 3.0));

    await tester.tap(find.text('Router'));
    await tester.pump();
    await tester.tap(find.byType(SketchCanvas));
    await tester.pumpAndSettle();
    expect(repo.layouts[homeId]!.router, isNotNull);

    await tester.tap(find.text('Spots'));
    await tester.pump();
    await tester.tap(find.byType(SketchCanvas));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(repo.layouts[homeId]!.spots.single.label, 'Desk');

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Room sketch: My home'), findsOneWidget);
    expect(find.text('1 room'), findsOneWidget);
  });

  testWidgets('room dialog rejects sizes outside 1–30 m', (tester) async {
    await pumpSagap(tester, repo: MemoryScanRepository());
    await openEditorForNewHome(tester);
    await tester.tap(find.text('Add room'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Width (m)'), '0.5');
    await tester.pump();
    expect(find.text('1–30 m'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add')).onPressed,
      isNull,
    );
  });

  testWidgets('edit and delete a selected room', (tester) async {
    final repo = MemoryScanRepository();
    await pumpSagap(tester, repo: repo);
    await openEditorForNewHome(tester);
    await addRoom(tester, name: 'Sala');
    final homeId = repo.homesById.keys.single;

    await tester.tap(find.byTooltip('Edit room'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Room name'), 'Living room');
    await tester.enterText(find.widgetWithText(TextField, 'Width (m)'), '4,5');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final edited = repo.layouts[homeId]!.rooms.single;
    expect((edited.name, edited.width), ('Living room', 4.5));

    await tester.tap(find.byTooltip('Delete room'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.layouts[homeId]!.rooms, isEmpty);
  });

  testWidgets('manual scan records a 5-reading spot and saves it with its position',
      (tester) async {
    final repo = MemoryScanRepository();
    final source = FakeSignalSource();
    await pumpSagap(tester, repo: repo, source: source);
    source.emit(connectedReading(1000, -60));
    await tester.pump(settle);

    await openEditorForNewHome(tester);
    await addRoom(tester, name: 'Kitchen', width: '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);
    expect(find.text('Recording · Sketch'), findsOneWidget);
    expect(find.text('Allow the camera?'), findsNothing);

    FilledButton recordButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Record here'));
    expect(recordButton().onPressed, isNull, reason: 'no position tapped yet');

    await tester.tap(find.byType(SketchCanvas));
    await tester.pump(settle);
    expect(recordButton().onPressed, isNotNull);

    await tester.tap(find.text('Record here'));
    await tester.pump();
    expect(find.text('Hold still… 0 of $manualReadingsPerSpot'), findsOneWidget);

    for (final (i, rssi) in [-60, -62, -64, -66, -68].indexed) {
      source.emit(connectedReading(2000 + i * 1000, rssi));
      await tester.pump(settle);
    }
    expect(find.text('1 spot recorded. Still needed: Kitchen 1/3'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('1 spot recorded on the sketch'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save scan to'), findsNothing, reason: 'saved to the sketched home');
    expect(find.text('Saved to My home'), findsOneWidget);
    final (_, scan) = repo.scansById.values.single;
    expect(scan.mode, ScanMode.manual);
    final sample = scan.samples.single;
    expect(sample.rssiDbm, -64);
    expect(sample.xM, closeTo(2.0, 0.01));
    expect(sample.yM, closeTo(1.5, 0.01));
  });

  testWidgets('pausing cancels a spot in progress; undo removes the last spot',
      (tester) async {
    final repo = MemoryScanRepository();
    final source = FakeSignalSource();
    await pumpSagap(tester, repo: repo, source: source);
    source.emit(connectedReading(1000, -60));
    await tester.pump(settle);
    await openEditorForNewHome(tester);
    await addRoom(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);

    await tester.tap(find.byType(SketchCanvas));
    await tester.pump(settle);
    await tester.tap(find.text('Record here'));
    await tester.pump();
    source.emit(connectedReading(2000, -60));
    await tester.pump(settle);

    await tester.tap(find.text('Pause'));
    await tester.pump(settle);
    expect(find.textContaining('Hold still'), findsNothing);

    await tester.tap(find.text('Resume'));
    await tester.pump(settle);
    await tester.tap(find.text('Record here'));
    await tester.pump();
    for (var i = 0; i < manualReadingsPerSpot; i++) {
      source.emit(connectedReading(3000 + i * 1000, -70));
      await tester.pump(settle);
    }
    expect(find.textContaining('1 spot recorded'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo last spot'));
    await tester.pump(settle);
    expect(find.textContaining('0 spots recorded'), findsOneWidget);
  });

  testWidgets('Stop using leaves manual mode', (tester) async {
    await pumpSagap(tester, repo: MemoryScanRepository());
    await openEditorForNewHome(tester);
    await addRoom(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Stop using'));
    await tester.pump();
    await tester.tap(find.text('Stop using'));
    await tester.pump();
    expect(find.text('Map with a room sketch'), findsOneWidget);
  });
}
