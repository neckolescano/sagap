import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/fixes.dart';
import 'package:sagap/domain/heatmap.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/sketch/room_dialog.dart';

SketchRoom room(int id, double x, double y, double w, double l, {bool outside = false}) =>
    SketchRoom(id: id, name: 'R$id', x: x, y: y, width: w, length: l, outside: outside);

void main() {
  group('gapsFor', () {
    // A is 3 × 3 at the origin.
    final a = room(1, 0, 0, 3, 3);

    test('nearest aligned room per side, edge to edge', () {
      final layout = HomeLayout(rooms: [
        a,
        room(2, 5, 1, 2, 2), // right, 2 m
        room(3, 9, 0, 2, 2), // right but farther, ignored
        room(4, 1, 4.5, 2, 2), // below, 1.5 m
        room(5, -4, 0, 2, 3), // left, 2 m
        room(6, 6, 6, 2, 2), // diagonal: not aligned on any side
      ]);
      final gaps = {for (final g in layout.gapsFor(a)) g.side: (g.neighbour.id, g.meters)};
      expect(gaps, {
        RoomSide.left: (5, 2.0),
        RoomSide.right: (2, 2.0),
        RoomSide.below: (4, 1.5),
      });
    });

    test('touching rooms have a 0 m gap', () {
      final layout = HomeLayout(rooms: [a, room(2, 3, 0, 2, 3)]);
      final gap = layout.gapsFor(a).single;
      expect((gap.side, gap.meters), (RoomSide.right, 0.0));
    });

    test('rooms that only share a corner are not aligned', () {
      final layout = HomeLayout(rooms: [a, room(2, 3, 3, 2, 2)]);
      expect(layout.gapsFor(a), isEmpty);
    });

    test('overlapping rooms are reported by overlapping(), not as gaps', () {
      final b = room(2, 2, 2, 3, 3);
      final layout = HomeLayout(rooms: [a, b]);
      expect(layout.gapsFor(a), isEmpty);
      expect(layout.overlapping(a).single.id, 2);
      expect(layout.overlapping(room(3, 10, 10, 1, 1)), isEmpty);
    });
  });

  group('placeBeside', () {
    final anchor = room(1, 2, 1, 4, 3); // x 2–6, y 1–4
    final moving = room(2, 20, 20, 2, 2);
    const layout = HomeLayout();

    test('each side lines up the edges and keeps the gap', () {
      SketchRoom place(RoomSide side) => layout.placeBeside(moving, anchor, side, 2.5);
      expect((place(RoomSide.right).x, place(RoomSide.right).y), (8.5, 1.0));
      expect((place(RoomSide.left).x, place(RoomSide.left).y), (-2.5, 1.0));
      expect((place(RoomSide.below).x, place(RoomSide.below).y), (2.0, 6.5));
      expect((place(RoomSide.above).x, place(RoomSide.above).y), (2.0, -3.5));
    });

    test('a gap of 0 makes the rooms share a wall', () {
      final placed = layout.placeBeside(moving, anchor, RoomSide.right, 0);
      final after = HomeLayout(rooms: [anchor, placed]);
      expect(after.gapsFor(placed).single.meters, 0.0);
    });

    test('snaps to the 0.5 m grid', () {
      expect(layout.placeBeside(moving, anchor, RoomSide.right, 1.2).x, 7.0);
    });

    test('rejects a negative or too-large gap', () {
      expect(() => layout.placeBeside(moving, anchor, RoomSide.right, -1), throwsArgumentError);
      expect(
        () => layout.placeBeside(moving, anchor, RoomSide.right, maxPlacementGapM + 0.5),
        throwsArgumentError,
      );
    });
  });

  test('parsePlacementGap accepts 0–50 m with a comma decimal', () {
    expect(parsePlacementGap('0'), 0.0);
    expect(parsePlacementGap('3,5'), 3.5);
    expect(parsePlacementGap('50'), 50.0);
    expect(parsePlacementGap('50.5'), isNull);
    expect(parsePlacementGap('-1'), isNull);
    expect(parsePlacementGap('two'), isNull);
  });

  test('routerDistanceM measures from the room centre', () {
    final r = room(1, 0, 0, 3, 4); // centre (1.5, 2)
    expect(const HomeLayout().routerDistanceM(r), isNull);
    expect(HomeLayout(router: const FloorPoint(0, 0)).routerDistanceM(r), closeTo(2.5, 1e-9));
  });

  group('outside rooms', () {
    test('need no minimum spots and are not home rooms', () {
      final layout = HomeLayout(rooms: [
        room(1, 0, 0, 3, 3),
        room(2, 5, 0, 3, 3, outside: true),
      ]);
      expect(layout.homeRooms.map((r) => r.id), [1]);
      expect(layout.roomsNeedingPoints(const []).map((r) => r.id), [1]);
      expect(layout.homeRoomAt(const FloorPoint(6, 1)), isNull);
      expect(layout.roomAt(const FloorPoint(6, 1))?.id, 2);
    });

    StoredSample at(double x, int rssi) => StoredSample(tMs: 0, rssiDbm: rssi, xM: x, yM: 0.25);
    // Cells x = 0.25 … 2.75; the four dead cells centre at x = 2.0.
    final map = buildHeatmap(
      [for (final (i, v) in [-50, -50, -90, -90, -90, -90].indexed) at(0.25 + i * 0.5, v)],
      minSamplesMeasured: 1,
    );

    test('a dead zone in an outside room is not a fix target', () {
      final outside = HomeLayout(rooms: [room(1, 1, 0, 2, 1, outside: true)]);
      expect(findTargets(map, outside), isEmpty);
      final home = HomeLayout(rooms: [room(1, 1, 0, 2, 1)]);
      expect(findTargets(map, home).single.label, 'R1');
    });

    test('an extender is never placed in an outside room', () {
      final line = buildHeatmap(
        [for (final (i, v) in [-40, -50, -55, -58, -62, -70, -90, -90].indexed) at(0.25 + i * 0.5, v)],
        minSamplesMeasured: 1,
      );
      const router = FloorPoint(0.25, 0.25);
      const target = FloorPoint(3.75, 0.25);
      expect(extenderSpot(line, router, target)!.x, closeTo(2.25, 1e-9));
      // The −62 cell at x = 2.25 is inside a neighbour's area.
      final layout = HomeLayout(rooms: [room(1, 2, 0, 1, 1, outside: true)]);
      expect(extenderSpot(line, router, target, layout: layout), isNull);
    });
  });
}
