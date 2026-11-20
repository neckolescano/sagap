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
  });

  /// Database id, or a negative id for a room not saved yet.
  final int id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double length;

  bool contains(FloorPoint p) =>
      p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + length;

  SketchRoom copyWith({
    int? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? length,
  }) =>
      SketchRoom(
        id: id ?? this.id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        length: length ?? this.length,
      );
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

  /// Number of [points] inside each room, keyed by room id.
  Map<int, int> pointsPerRoom(Iterable<FloorPoint> points) {
    final counts = {for (final r in rooms) r.id: 0};
    for (final p in points) {
      final room = roomAt(p);
      if (room != null) counts[room.id] = counts[room.id]! + 1;
    }
    return counts;
  }

  /// Rooms with fewer than [minPointsPerRoom] recorded points.
  List<SketchRoom> roomsNeedingPoints(Iterable<FloorPoint> points) {
    final counts = pointsPerRoom(points);
    return [for (final r in rooms) if (counts[r.id]! < minPointsPerRoom) r];
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
