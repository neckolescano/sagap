import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/features/sketch/room_dialog.dart';
import 'package:sagap/features/sketch/sketch_canvas.dart';

void main() {
  test('snapToGrid rounds to 0.5 m', () {
    expect(snapToGrid(1.2), 1.0);
    expect(snapToGrid(1.26), 1.5);
    expect(snapToGrid(-0.3), -0.5);
  });

  test('clampRoomSize keeps 1–30 m and snaps', () {
    expect(clampRoomSize(0.2), 1.0);
    expect(clampRoomSize(45), 30.0);
    expect(clampRoomSize(3.3), 3.5);
  });

  test('addRoom places each new room to the right of the last', () {
    var layout = const HomeLayout();
    layout = layout.addRoom(id: 1, name: 'Sala', width: 4, length: 3);
    layout = layout.addRoom(id: 2, name: 'Kitchen', width: 2.6, length: 3);
    expect(layout.rooms[0].x, 0);
    expect(layout.rooms[1].x, 4);
    expect(layout.rooms[1].width, 2.5);
  });

  test('updateRoom snaps position and size', () {
    var layout = const HomeLayout().addRoom(id: 1, name: 'A', width: 3, length: 3);
    layout = layout.updateRoom(layout.rooms.single.copyWith(x: 1.3, y: -0.7, width: 0.4));
    final room = layout.rooms.single;
    expect((room.x, room.y, room.width), (1.5, -0.5, 1.0));
  });

  test('roomAt returns the topmost room containing the point', () {
    final layout = const HomeLayout()
        .addRoom(id: 1, name: 'Big', width: 6, length: 6)
        .updateRoom(const SketchRoom(id: 1, name: 'Big', x: 0, y: 0, width: 6, length: 6))
        .addRoom(id: 2, name: 'Small', width: 2, length: 2)
        .updateRoom(const SketchRoom(id: 2, name: 'Small', x: 1, y: 1, width: 2, length: 2));
    expect(layout.roomAt(const FloorPoint(2, 2))?.name, 'Small');
    expect(layout.roomAt(const FloorPoint(5, 5))?.name, 'Big');
    expect(layout.roomAt(const FloorPoint(9, 9)), isNull);
  });

  test('coverage counts points per room and lists rooms under 3', () {
    final layout = const HomeLayout()
        .addRoom(id: 1, name: 'Sala', width: 4, length: 4)
        .addRoom(id: 2, name: 'Kitchen', width: 2, length: 4);
    final points = [
      const FloorPoint(1, 1),
      const FloorPoint(2, 2),
      const FloorPoint(3, 3),
      const FloorPoint(5, 1),
      const FloorPoint(20, 20),
    ];
    expect(layout.pointsPerRoom(points), {1: 3, 2: 1});
    expect([for (final r in layout.roomsNeedingPoints(points)) r.name], ['Kitchen']);
  });

  test('router and spots snap to the grid; removal works', () {
    var layout = const HomeLayout().setRouter(const FloorPoint(1.1, 2.4));
    expect((layout.router!.x, layout.router!.y), (1.0, 2.5));
    layout = layout.addSpot(const PrioritySpot(id: 7, label: 'Desk', point: FloorPoint(0.3, 0.8)));
    expect((layout.spots.single.point.x, layout.spots.single.point.y), (0.5, 1.0));
    layout = layout.removeSpot(7).clearRouter();
    expect(layout.spots, isEmpty);
    expect(layout.router, isNull);
  });

  test('medianDbm takes the weaker middle for even counts; empty throws', () {
    expect(medianDbm([-60, -62, -64, -66, -68]), -64);
    expect(medianDbm([-50, -70]), -70);
    expect(() => medianDbm([]), throwsArgumentError);
  });

  test('parseRoomSize accepts 1–30 m with dot or comma', () {
    expect(parseRoomSize('3'), 3.0);
    expect(parseRoomSize(' 2,5 '), 2.5);
    expect(parseRoomSize('0.5'), isNull);
    expect(parseRoomSize('31'), isNull);
    expect(parseRoomSize('abc'), isNull);
  });

  test('SketchTransform centres content and round-trips', () {
    final layout = const HomeLayout().addRoom(id: 1, name: 'A', width: 4, length: 3);
    final t = SketchTransform.fit(layout, const Size(300, 300));
    // 6 m minimum span over 300 px = 50 px/m; room centre (2, 1.5) at canvas centre.
    expect(t.pxPerM, 50);
    expect(t.toPx(const FloorPoint(2, 1.5)), const Offset(150, 150));
    final back = t.toMeters(const Offset(200, 100));
    expect((back.x, back.y), (3.0, 0.5));
  });
}
