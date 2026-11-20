import 'home_layout.dart';
import 'path_track.dart';

/// An axis-aligned wall segment, in meters.
class Wall {
  const Wall.horizontal({required this.at, required this.from, required this.to})
      : horizontal = true;
  const Wall.vertical({required this.at, required this.from, required this.to})
      : horizontal = false;

  /// True: runs along x at y = [at]. False: runs along y at x = [at].
  final bool horizontal;
  final double at;
  final double from;
  final double to;

  /// Whether the straight line a → b passes through this wall.
  /// Touching the wall's line without crossing it does not count.
  bool crossedBy(FloorPoint a, FloorPoint b) {
    final (pa, pb, qa, qb) =
        horizontal ? (a.y, b.y, a.x, b.x) : (a.x, b.x, a.y, b.y);
    if ((pa - at) * (pb - at) >= 0) return false;
    final t = (at - pa) / (pb - pa);
    final cross = qa + t * (qb - qa);
    return cross >= from && cross <= to;
  }

  @override
  String toString() => horizontal ? 'H y=$at x=$from..$to' : 'V x=$at y=$from..$to';
}

/// Walls from the sketched room edges (SPEC.md §10 step 4).
///
/// Collinear edges that touch or overlap (e.g. the shared wall of two
/// neighbouring rooms) merge into one wall, so a shared wall counts once.
List<Wall> wallsFromRooms(HomeLayout layout) {
  final horizontal = <double, List<(double, double)>>{};
  final vertical = <double, List<(double, double)>>{};
  for (final r in layout.rooms) {
    horizontal.putIfAbsent(r.y, () => []).add((r.x, r.x + r.width));
    horizontal.putIfAbsent(r.y + r.length, () => []).add((r.x, r.x + r.width));
    vertical.putIfAbsent(r.x, () => []).add((r.y, r.y + r.length));
    vertical.putIfAbsent(r.x + r.width, () => []).add((r.y, r.y + r.length));
  }
  final walls = <Wall>[];
  for (final MapEntry(key: at, value: spans) in horizontal.entries) {
    for (final (from, to) in _merge(spans)) {
      walls.add(Wall.horizontal(at: at, from: from, to: to));
    }
  }
  for (final MapEntry(key: at, value: spans) in vertical.entries) {
    for (final (from, to) in _merge(spans)) {
      walls.add(Wall.vertical(at: at, from: from, to: to));
    }
  }
  return walls;
}

List<(double, double)> _merge(List<(double, double)> spans) {
  final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(double, double)>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && span.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, span.$2 > last.$2 ? span.$2 : last.$2));
    } else {
      merged.add(span);
    }
  }
  return merged;
}

/// Indices of [walls] crossed by the line a → b.
List<int> wallsCrossed(List<Wall> walls, FloorPoint a, FloorPoint b) => [
      for (final (i, w) in walls.indexed)
        if (w.crossedBy(a, b)) i,
    ];
