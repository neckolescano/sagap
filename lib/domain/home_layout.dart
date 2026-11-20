import 'path_track.dart';

/// Sketch grid step, in meters. Rooms and markers snap to it (SPEC.md §10).
const double sketchGridM = 0.5;

/// Room size limits, in meters.
const double minRoomSizeM = 1;
const double maxRoomSizeM = 30;

/// Gap left between an auto-placed room and the previous one.
const double _autoPlaceGapM = 0;

/// Recorded spots a room needs before it counts as covered (SPEC.md §10).
const int minPointsPerRoom = 3;

/// Largest gap accepted when placing a room beside another, in meters.
const double maxPlacementGapM = 50;

/// One tap of a nudge arrow moves the selected room by this much.
const double nudgeStepM = sketchGridM;

double snapToGrid(double meters) =>
    (meters / sketchGridM).round() * sketchGridM;

double clampRoomSize(double meters) =>
    snapToGrid(meters.clamp(minRoomSizeM, maxRoomSizeM));

/// A hand-drawn room: an axis-aligned rectangle, top-left at (x, y), meters.
class SketchRoom {
  const SketchRoom({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.length,
    this.outside = false,
  });

  /// Outside your home: a yard, hallway or a neighbour's place. Its walls
  /// still count in the signal model, but it isn't a router spot, doesn't
  /// count toward dead-zone area and needs no minimum number of spots.
  final bool outside;

  /// Database id, or a negative id for a room not saved yet.
  final int id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double length;

  double get right => x + width;
  double get bottom => y + length;
  FloorPoint get center => FloorPoint(x + width / 2, y + length / 2);

  bool contains(FloorPoint p) =>
      p.x >= x && p.x <= right && p.y >= y && p.y <= bottom;

  /// True when the two rooms share some area (touching edges don't count).
  bool overlaps(SketchRoom o) =>
      x < o.right && o.x < right && y < o.bottom && o.y < bottom;

  SketchRoom copyWith({
    int? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? length,
    bool? outside,
  }) =>
      SketchRoom(
        id: id ?? this.id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        length: length ?? this.length,
        outside: outside ?? this.outside,
      );
}

/// Side of a room, as seen on the sketch (up = top of the screen).
enum RoomSide { left, right, above, below }

/// Clear distance from a room's edge to the nearest room on one [side].
class RoomGap {
  const RoomGap({required this.side, required this.neighbour, required this.meters});

  final RoomSide side;
  final SketchRoom neighbour;

  /// 0 when the rooms touch.
  final double meters;
}

/// A labelled place the user cares about (desk, TV, bed).
class PrioritySpot {
  const PrioritySpot({required this.id, required this.label, required this.point});

  final int id;
  final String label;
  final FloorPoint point;
}

/// One home's sketch: rooms, router and priority spots. Immutable.
class HomeLayout {
  const HomeLayout({
    this.rooms = const [],
    this.router,
    this.spots = const [],
  });

  final List<SketchRoom> rooms;
  final FloorPoint? router;
  final List<PrioritySpot> spots;

  bool get isEmpty => rooms.isEmpty;

  HomeLayout _with({
    List<SketchRoom>? rooms,
    FloorPoint? router,
    bool clearRouter = false,
    List<PrioritySpot>? spots,
  }) =>
      HomeLayout(
        rooms: rooms ?? this.rooms,
        router: clearRouter ? null : (router ?? this.router),
        spots: spots ?? this.spots,
      );

  /// Adds a room to the right of the rightmost room (or at the origin).
  HomeLayout addRoom({
    required int id,
    required String name,
    required double width,
    required double length,
    bool outside = false,
  }) {
    final right = rooms.isEmpty
        ? 0.0
        : rooms.map((r) => r.x + r.width).reduce((a, b) => a > b ? a : b);
    final room = SketchRoom(
      id: id,
      name: name,
      x: snapToGrid(right + _autoPlaceGapM),
      y: 0,
      width: clampRoomSize(width),
      length: clampRoomSize(length),
      outside: outside,
    );
    return _with(rooms: [...rooms, room]);
  }

  /// Replaces the room with the same id, snapping position and size.
  HomeLayout updateRoom(SketchRoom room) {
    final snapped = room.copyWith(
      x: snapToGrid(room.x),
      y: snapToGrid(room.y),
      width: clampRoomSize(room.width),
      length: clampRoomSize(room.length),
    );
    return _with(rooms: [for (final r in rooms) r.id == room.id ? snapped : r]);
  }

  HomeLayout removeRoom(int roomId) =>
      _with(rooms: [for (final r in rooms) if (r.id != roomId) r]);

  HomeLayout setRouter(FloorPoint p) =>
      _with(router: FloorPoint(snapToGrid(p.x), snapToGrid(p.y)));

  HomeLayout clearRouter() => _with(clearRouter: true);

  HomeLayout addSpot(PrioritySpot spot) => _with(spots: [
        ...spots,
        PrioritySpot(
          id: spot.id,
          label: spot.label,
          point: FloorPoint(snapToGrid(spot.point.x), snapToGrid(spot.point.y)),
        ),
      ]);

  HomeLayout removeSpot(int spotId) =>
      _with(spots: [for (final s in spots) if (s.id != spotId) s]);

  /// The topmost (last drawn) room containing [p], or null.
  SketchRoom? roomAt(FloorPoint p) {
    for (final room in rooms.reversed) {
      if (room.contains(p)) return room;
    }
    return null;
  }

  /// Rooms inside your home (not marked outside).
  List<SketchRoom> get homeRooms => [for (final r in rooms) if (!r.outside) r];

  /// The topmost room inside your home containing [p], or null.
  SketchRoom? homeRoomAt(FloorPoint p) {
    for (final room in homeRooms.reversed) {
      if (room.contains(p)) return room;
    }
    return null;
  }

  /// Other rooms sharing area with [room].
  List<SketchRoom> overlapping(SketchRoom room) =>
      [for (final r in rooms) if (r.id != room.id && r.overlaps(room)) r];

  /// Nearest room on each side of [room], measured edge to edge.
  ///
  /// A room counts for a side only if it lines up with [room] across that
  /// side (their spans overlap), so the gap is a straight-line distance.
  /// Overlapping rooms are left out; see [overlapping].
  List<RoomGap> gapsFor(SketchRoom room) {
    final best = <RoomSide, RoomGap>{};
    for (final o in rooms) {
      if (o.id == room.id || o.overlaps(room)) continue;
      final alignedX = o.x < room.right && room.x < o.right;
      final alignedY = o.y < room.bottom && room.y < o.bottom;
      final candidates = <(RoomSide, double)>[
        if (alignedY && o.right <= room.x) (RoomSide.left, room.x - o.right),
        if (alignedY && o.x >= room.right) (RoomSide.right, o.x - room.right),
        if (alignedX && o.bottom <= room.y) (RoomSide.above, room.y - o.bottom),
        if (alignedX && o.y >= room.bottom) (RoomSide.below, o.y - room.bottom),
      ];
      for (final (side, meters) in candidates) {
        final current = best[side];
        if (current == null || meters < current.meters) {
          best[side] = RoomGap(side: side, neighbour: o, meters: meters);
        }
      }
    }
    return [for (final side in RoomSide.values) ?best[side]];
  }

  /// [room] moved to [side] of [anchor], [gapM] meters away, with the
  /// edges lined up (top edges for left/right, left edges for above/below).
  /// Snapped to the grid.
  SketchRoom placeBeside(SketchRoom room, SketchRoom anchor, RoomSide side, double gapM) {
    if (gapM < 0 || gapM > maxPlacementGapM) {
      throw ArgumentError.value(gapM, 'gapM', 'must be 0 to $maxPlacementGapM m');
    }
    final (x, y) = switch (side) {
      RoomSide.left => (anchor.x - gapM - room.width, anchor.y),
      RoomSide.right => (anchor.right + gapM, anchor.y),
      RoomSide.above => (anchor.x, anchor.y - gapM - room.length),
      RoomSide.below => (anchor.x, anchor.bottom + gapM),
    };
    return room.copyWith(x: snapToGrid(x), y: snapToGrid(y));
  }

  /// Straight-line distance from the centre of [room] to the router, or
  /// null without a router.
  double? routerDistanceM(SketchRoom room) => router?.distanceTo(room.center);

  /// Number of [points] inside each room, keyed by room id.
  Map<int, int> pointsPerRoom(Iterable<FloorPoint> points) {
    final counts = {for (final r in rooms) r.id: 0};
    for (final p in points) {
      final room = roomAt(p);
      if (room != null) counts[room.id] = counts[room.id]! + 1;
    }
    return counts;
  }

  /// Home rooms with fewer than [minPointsPerRoom] recorded points.
  /// Outside rooms are optional, so they are never listed.
  List<SketchRoom> roomsNeedingPoints(Iterable<FloorPoint> points) {
    final counts = pointsPerRoom(points);
    return [for (final r in homeRooms) if (counts[r.id]! < minPointsPerRoom) r];
  }
}

/// Number of readings averaged for one manual spot (SPEC.md §10: 5 s at 1 Hz).
const int manualReadingsPerSpot = 5;

/// Median of [values]; the weaker middle value for an even count.
int medianDbm(List<int> values) {
  if (values.isEmpty) throw ArgumentError.value(values, 'values', 'is empty');
  final sorted = [...values]..sort();
  return sorted[(sorted.length - 1) ~/ 2];
}
