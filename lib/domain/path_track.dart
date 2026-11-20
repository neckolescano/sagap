import 'dart:math' as math;

import '../platform/ar_bridge.dart';

/// Point on the floor plane, in meters: x = ARCore x, y = ARCore z.
class FloorPoint {
  const FloorPoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(FloorPoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
}

/// Moves smaller than this are treated as tracking jitter and not drawn.
const double minPathStepM = 0.05;

/// Walked path from AR poses (SPEC.md §7). Immutable.
///
/// Used for the M2 tape test: walk a measured line and compare
/// [distanceFromStartM] to the tape; return to the start and read
/// [distanceFromStartM] as the loop-closure error.
class PathTrack {
  const PathTrack._(this.segments, this.walkedM, this._breakPending);

  const PathTrack.empty() : this._(const [], 0, false);

  /// Continuous runs of tracked points; a new run starts after tracking loss.
  final List<List<FloorPoint>> segments;

  /// Sum of drawn steps, in meters.
  final double walkedM;

  final bool _breakPending;

  FloorPoint? get start => segments.isEmpty ? null : segments.first.first;
  FloorPoint? get current => segments.isEmpty ? null : segments.last.last;

  /// Straight-line distance from the first tracked point, in meters.
  double get distanceFromStartM {
    final s = start;
    final c = current;
    return s == null || c == null ? 0 : s.distanceTo(c);
  }

  PathTrack add(PoseSample pose) {
    if (pose.tracking != ArTracking.tracking) {
      return segments.isEmpty ? this : PathTrack._(segments, walkedM, true);
    }
    final point = FloorPoint(pose.x, pose.z);
    final last = current;
    if (last == null) {
      return PathTrack._([[point]], 0, false);
    }
    if (_breakPending) {
      // Position may have jumped while lost; don't count it as walking.
      return PathTrack._([...segments, [point]], walkedM, false);
    }
    final step = last.distanceTo(point);
    if (step < minPathStepM) return this;
    final updated = [...segments];
    updated[updated.length - 1] = [...updated.last, point];
    return PathTrack._(updated, walkedM + step, false);
  }
}
