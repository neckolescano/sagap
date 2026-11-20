import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/compare.dart';
import 'package:sagap/domain/heatmap.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

StoredSample at(double x, double y, int rssi) =>
    StoredSample(tMs: 0, rssiDbm: rssi, xM: x, yM: y);

WalkData walk(List<StoredSample> samples, {List<FloorPoint> noSignal = const []}) => WalkData(
      heatmap: buildHeatmap(samples, minSamplesMeasured: 1),
      samples: samples,
      noSignalSpots: noSignal,
    );

void main() {
  const layout = HomeLayout(
    rooms: [
      SketchRoom(id: 1, name: 'Sala', x: 0, y: 0, width: 4, length: 3),
      SketchRoom(id: 2, name: 'Bedroom', x: 4.5, y: 0, width: 3, length: 3),
      SketchRoom(id: 3, name: 'Yard', x: 8, y: 0, width: 3, length: 3, outside: true),
    ],
    spots: [PrioritySpot(id: 1, label: 'Desk', point: FloorPoint(5.25, 1.25))],
  );

  test('rooms, spots and the whole home, before vs after', () {
    final result = compareWalks(
      before: walk([
        at(1.25, 1.25, -50), at(2.25, 2.25, -54), at(3.25, 1.25, -52), // Sala
        at(5.25, 1.25, -80), at(6.25, 2.25, -84), // Bedroom
        at(9.25, 1.25, -90), // Yard (outside)
      ], noSignal: const [FloorPoint(10, 2), FloorPoint(10.5, 2)]),
      after: walk([
        at(1.25, 1.25, -51), at(2.25, 2.25, -53), // Sala
        at(5.25, 1.25, -66), at(6.25, 2.25, -70), // Bedroom
      ]),
      layout: layout,
    );

    // Sala −52 → −53: within normal variation.
    final sala = result.rooms.firstWhere((r) => r.name == 'Sala');
    expect((sala.beforeDbm, sala.afterDbm, sala.deltaDb), (-52, -53, -1));
    expect(sala.verdict, ChangeVerdict.same);
    // Bedroom: median of two is the weaker one, −84 → −70.
    final bedroom = result.rooms.firstWhere((r) => r.name == 'Bedroom');
    expect((bedroom.beforeDbm, bedroom.afterDbm, bedroom.deltaDb), (-84, -70, 14));
    expect(bedroom.verdict, ChangeVerdict.better);
    expect(result.rooms.map((r) => r.name), ['Sala', 'Bedroom'], reason: 'Yard is outside');

    // Whole home: [−90 −84 −80 −54 −52 −50] → −80; [−70 −66 −53 −51] → −66.
    expect((result.overall.beforeDbm, result.overall.afterDbm), (-80, -66));

    // Desk sits in a measured cell in both walks.
    final desk = result.spots.single;
    expect((desk.name, desk.beforeDbm, desk.afterDbm, desk.predicted), ('Desk', -80, -66, false));

    expect((result.noSignalBefore, result.noSignalAfter), (2, 0));
  });

  test('a room not recorded in one walk is unknown, not worse', () {
    final result = compareWalks(
      before: walk([at(1.25, 1.25, -60)]),
      after: walk([at(5.25, 1.25, -60)]),
      layout: layout,
    );
    final sala = result.rooms.firstWhere((r) => r.name == 'Sala');
    expect((sala.beforeDbm, sala.afterDbm, sala.deltaDb), (-60, null, null));
    expect(sala.verdict, ChangeVerdict.unknown);
  });

  test('dead-zone area counts home rooms only', () {
    HeatCell dead() => const HeatCell(dbm: -90, measured: true, sampleCount: 1);
    HeatCell good() => const HeatCell(dbm: -50, measured: true, sampleCount: 1);
    // One row of 0.5 m cells from x = 0: 4 dead cells in Sala (x 0–2) and
    // 4 dead cells in the Yard (x 8–10), split by good cells.
    final before = Heatmap.fromCells(cols: 20, cells: [
      for (var i = 0; i < 20; i++) (i < 4 || i >= 16) ? dead() : good(),
    ]);
    final after = Heatmap.fromCells(cols: 20, cells: [
      for (var i = 0; i < 20; i++) i >= 16 ? dead() : good(),
    ]);
    final result = compareWalks(
      before: WalkData(heatmap: before, samples: const []),
      after: WalkData(heatmap: after, samples: const []),
      layout: layout,
    );
    expect(result.deadAreaBeforeM2, closeTo(1.0, 1e-9));
    expect(result.deadAreaAfterM2, closeTo(0.0, 1e-9));
  });

  test('verdict thresholds are ±3 dB', () {
    PlaceChange c(int before, int after) =>
        PlaceChange(name: 'x', beforeDbm: before, afterDbm: after);
    expect(c(-70, -67).verdict, ChangeVerdict.better);
    expect(c(-70, -68).verdict, ChangeVerdict.same);
    expect(c(-70, -72).verdict, ChangeVerdict.same);
    expect(c(-70, -73).verdict, ChangeVerdict.worse);
  });
}
