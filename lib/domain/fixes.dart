import 'dart:math' as math;

import '../core/signal/signal_quality.dart';
import 'channel_check.dart';
import 'heatmap.dart';
import 'home_layout.dart';
import 'path_track.dart';

/// Fix rules (SPEC.md §9). All proposals; tune here.
abstract final class FixSettings {
  /// Connected dead-zone cells needed to count as a dead zone.
  static const int minDeadZoneCells = 4;

  /// Extender spot signal band, in dBm (decided: about −60 to −65).
  static const int extenderMinDbm = -65;
  static const int extenderMaxDbm = -60;

  /// How far a candidate may be from the router → target line, in meters.
  static const double extenderLineToleranceM = 1.5;

  /// Two targets this far apart in direction (degrees, seen from the router)
  /// count as "different directions" for the mesh rule.
  static const double meshMinAngleDeg = 90;
}

enum CostTier { free, lowCost, higherCost }

enum Evidence { measured, measuredRelative, predicted, notEstimated }

/// Something with weak signal that a fix should help.
class FixTarget {
  const FixTarget({required this.label, required this.point, this.areaM2});

  final String label;
  final FloorPoint point;

  /// Area for dead zones; null for priority spots.
  final double? areaM2;
}

enum FixKind { hotspotResult, moveRouter, extender, mesh, channel, bandTip, antennaTip }

/// One recommendation card: what, where, expected improvement (SPEC.md §9).
class Fix {
  const Fix({
    required this.kind,
    required this.tier,
    required this.what,
    required this.where,
    required this.improvement,
    required this.evidence,
    this.points = const [],
    this.targetsImproved = 0,
  });

  final FixKind kind;
  final CostTier tier;
  final String what;
  final String where;
  final String improvement;
  final Evidence evidence;

  /// Map pins for this fix (extender / mesh node spots).
  final List<FloorPoint> points;

  /// Targets this fix is meant to help, for ranking.
  final int targetsImproved;
}

/// A connected group of dead-zone cells.
class DeadZone {
  const DeadZone({required this.cells, required this.centroid, required this.areaM2});

  final List<(int col, int row)> cells;
  final FloorPoint centroid;
  final double areaM2;
}

FloorPoint _cellCenter(Heatmap map, int col, int row) {
  final o = map.cellOrigin(col, row);
  return FloorPoint(o.x + map.cellM / 2, o.y + map.cellM / 2);
}

SignalQuality _quality(double dbm) =>
    signalQualityFor(dbm.round().clamp(validRssiMinDbm, validRssiMaxDbm));

/// Groups of ≥ [FixSettings.minDeadZoneCells] 4-connected dead-zone cells.
List<DeadZone> findDeadZones(Heatmap map) {
  final seen = <int>{};
  final zones = <DeadZone>[];
  bool isDead(int col, int row) {
    final cell = map.cell(col, row);
    return cell != null && _quality(cell.dbm) == SignalQuality.deadZone;
  }

  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final start = row * map.cols + col;
      if (seen.contains(start) || !isDead(col, row)) continue;
      final group = <(int, int)>[];
      final queue = [(col, row)];
      seen.add(start);
      while (queue.isNotEmpty) {
        final (c, r) = queue.removeLast();
        group.add((c, r));
        for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nc = c + dc;
          final nr = r + dr;
          if (nc < 0 || nr < 0 || nc >= map.cols || nr >= map.rows) continue;
          final i = nr * map.cols + nc;
          if (seen.contains(i) || !isDead(nc, nr)) continue;
          seen.add(i);
          queue.add((nc, nr));
        }
      }
      if (group.length < FixSettings.minDeadZoneCells) continue;
      final centers = [for (final (c, r) in group) _cellCenter(map, c, r)];
      zones.add(DeadZone(
        cells: group,
        centroid: FloorPoint(
          centers.map((p) => p.x).reduce((a, b) => a + b) / centers.length,
          centers.map((p) => p.y).reduce((a, b) => a + b) / centers.length,
        ),
        areaM2: group.length * map.cellM * map.cellM,
      ));
    }
  }
  return zones;
}

/// Dead zones plus priority spots that are Weak or Dead (SPEC.md §9).
List<FixTarget> findTargets(Heatmap map, HomeLayout layout) {
  final targets = <FixTarget>[];
  // A dead zone in the yard or at a neighbour's is not something to fix.
  final zones = [
    for (final z in findDeadZones(map))
      if (!_isOutside(layout, z.centroid)) z,
  ];
  for (final (i, zone) in zones.indexed) {
    final room = layout.roomAt(zone.centroid)?.name;
    targets.add(FixTarget(
      label: room ?? (zones.length == 1 ? 'the dead zone' : 'dead zone ${i + 1}'),
      point: zone.centroid,
      areaM2: zone.areaM2,
    ));
  }
  for (final spot in layout.spots) {
    final cell = map.cellAt(spot.point);
    if (cell == null) continue;
    final q = _quality(cell.dbm);
    if (q == SignalQuality.weak || q == SignalQuality.deadZone) {
      targets.add(FixTarget(label: spot.label, point: spot.point));
    }
  }
  return targets;
}

/// Total dead-zone area in m², leaving out zones in outside rooms.
double homeDeadAreaM2(Heatmap map, HomeLayout layout) => [
      for (final z in findDeadZones(map))
        if (!_isOutside(layout, z.centroid)) z.areaM2,
    ].fold(0.0, (a, b) => a + b);

/// True when [p] is in an outside room and in no home room.
bool _isOutside(HomeLayout layout, FloorPoint p) =>
    layout.homeRoomAt(p) == null && (layout.roomAt(p)?.outside ?? false);

double _distanceToSegment(FloorPoint p, FloorPoint a, FloorPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq).clamp(0.0, 1.0);
  return p.distanceTo(FloorPoint(a.x + t * dx, a.y + t * dy));
}

/// Extender spot for [target] (SPEC.md §9A): a **measured** cell at −65…−60
/// dBm within 1.5 m of the router → target line, nearest the target.
/// Null when there is none; predicted cells are never used.
/// Cells inside an outside room of [layout] (yard, neighbour) are skipped.
FloorPoint? extenderSpot(
  Heatmap map,
  FloorPoint router,
  FloorPoint target, {
  HomeLayout layout = const HomeLayout(),
}) {
  FloorPoint? best;
  var bestDistance = double.infinity;
  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final cell = map.cell(col, row);
      if (cell == null || !cell.measured) continue;
      if (cell.dbm < FixSettings.extenderMinDbm || cell.dbm > FixSettings.extenderMaxDbm) {
        continue;
      }
      final center = _cellCenter(map, col, row);
      if (_distanceToSegment(center, router, target) > FixSettings.extenderLineToleranceM) {
        continue;
      }
      if (_isOutside(layout, center)) continue;
      final d = center.distanceTo(target);
      if (d < bestDistance) {
        best = center;
        bestDistance = d;
      }
    }
  }
  return best;
}

double _angleDeg(FloorPoint from, FloorPoint to) =>
    math.atan2(to.y - from.y, to.x - from.x) * 180 / math.pi;

/// True when two targets lie more than [FixSettings.meshMinAngleDeg] apart
/// in direction, seen from the router.
bool targetsInDifferentDirections(FloorPoint router, List<FixTarget> targets) {
  for (var i = 0; i < targets.length; i++) {
    for (var j = i + 1; j < targets.length; j++) {
      var diff = (_angleDeg(router, targets[i].point) - _angleDeg(router, targets[j].point)).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff > FixSettings.meshMinAngleDeg) return true;
    }
  }
  return false;
}

String _whereLabel(HomeLayout layout, FloorPoint router, FloorPoint p) {
  final room = layout.roomAt(p)?.name;
  final meters = router.distanceTo(p).toStringAsFixed(1);
  return room == null ? '$meters m from the router' : 'In $room, $meters m from the router';
}

String _join(List<String> labels) => switch (labels.length) {
      0 => '',
      1 => labels.single,
      _ => '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}',
    };

/// Builds the fix cards, ranked Free → Low cost → Higher cost, then by how
/// many targets each helps (SPEC.md §9).
///
/// [router] is the sketched router, or for AR scans where the walk started.
/// Null router → no extender or mesh spot can be placed.
List<Fix> buildFixes({
  required Heatmap map,
  required HomeLayout layout,
  required FloorPoint? router,
  required List<ChannelCheck> channelChecks,
  required bool channelCheckAvailable,
  Fix? moveRouter,
  Fix? hotspotResult,
}) {
  final targets = findTargets(map, layout);
  final fixes = <Fix>[];
  if (targets.isEmpty) return fixes;
  if (hotspotResult != null) fixes.add(hotspotResult);
  if (moveRouter != null) fixes.add(moveRouter);

  // Free: channel.
  final advice = adviseChannel(channelChecks);
  if (advice != null) {
    fixes.add(Fix(
      kind: FixKind.channel,
      tier: CostTier.free,
      what: 'Change the Wi-Fi channel in your router settings',
      where: 'Your Wi-Fi is on channel ${advice.ownChannel} with ${advice.ownCount} '
          'strong nearby networks. Channel ${advice.betterChannel} had '
          '${advice.betterCount}.',
      improvement: 'Not estimated. Re-walk after changing it to check.',
      evidence: Evidence.notEstimated,
      targetsImproved: targets.length,
    ));
  } else if (!channelCheckAvailable) {
    fixes.add(Fix(
      kind: FixKind.channel,
      tier: CostTier.free,
      what: 'Check your Wi-Fi channel',
      where: "Sagap couldn't list nearby networks (location is off or not "
          'allowed). Your router settings page shows which channel it uses.',
      improvement: 'Not estimated.',
      evidence: Evidence.notEstimated,
      targetsImproved: targets.length,
    ));
  }

  // Free: tips from the notes (band, antennas).
  fixes.add(Fix(
    kind: FixKind.bandTip,
    tier: CostTier.free,
    what: 'Try the other Wi-Fi band',
    where: 'If your router has both 2.4 GHz and 5 GHz, connect to the other one '
        'and re-walk ${_join([for (final t in targets) t.label])}.',
    improvement: 'Not estimated. Re-walk to compare.',
    evidence: Evidence.notEstimated,
    targetsImproved: targets.length,
  ));
  fixes.add(const Fix(
    kind: FixKind.antennaTip,
    tier: CostTier.free,
    what: 'Adjust the router antennas',
    where: 'If your router has antennas you can move, try a different angle, '
        'then re-walk.',
    improvement: 'Not estimated. Re-walk to compare.',
    evidence: Evidence.notEstimated,
  ));

  // Low cost: extender per target (merged when one spot serves several).
  final spots = <FloorPoint, List<FixTarget>>{};
  final unreachable = <FixTarget>[];
  if (router != null) {
    for (final target in targets) {
      final spot = extenderSpot(map, router, target.point, layout: layout);
      if (spot == null) {
        unreachable.add(target);
      } else {
        spots.putIfAbsent(spot, () => []).add(target);
      }
    }
    for (final MapEntry(key: spot, value: served) in spots.entries) {
      final cell = map.cellAt(spot)!;
      final dbm = cell.dbm.round();
      fixes.add(Fix(
        kind: FixKind.extender,
        tier: CostTier.lowCost,
        what: 'Put a Wi-Fi extender here',
        where: _whereLabel(layout, router, spot),
        improvement: 'Signal at this spot is ${_quality(cell.dbm).label} '
            '(measured, ${dbm < 0 ? '−${-dbm}' : '$dbm'} dBm), between the router and '
            '${_join([for (final t in served) t.label])}. How much it helps there '
            "isn't estimated: re-walk after installing to check.",
        evidence: Evidence.measured,
        points: [spot],
        targetsImproved: served.length,
      ));
    }
    for (final target in unreachable) {
      fixes.add(Fix(
        kind: FixKind.extender,
        tier: CostTier.lowCost,
        what: 'Walk the area between the router and ${target.label} again',
        where: 'No measured spot there has Good signal (−65 to −60 dBm) yet, so '
            'an extender spot cannot be suggested.',
        improvement: 'Not estimated.',
        evidence: Evidence.notEstimated,
      ));
    }

    // Higher cost: mesh when targets lie in different directions and one
    // extender spot cannot cover them all.
    if (targets.length >= 2 &&
        spots.length != 1 &&
        targetsInDifferentDirections(router, targets)) {
      fixes.add(Fix(
        kind: FixKind.mesh,
        tier: CostTier.higherCost,
        what: 'Consider a mesh Wi-Fi system',
        where: spots.isEmpty
            ? 'Weak areas are in different directions from the router.'
            : 'Weak areas are in different directions from the router. '
                'Node spots are marked on the map.',
        improvement: 'Not estimated. Re-walk after setting it up to check.',
        evidence: Evidence.notEstimated,
        points: spots.keys.toList(),
        targetsImproved: targets.length,
      ));
    }
  } else {
    fixes.add(const Fix(
      kind: FixKind.extender,
      tier: CostTier.lowCost,
      what: 'Mark your router to get an extender spot',
      where: 'Place the router on your room sketch, then open fixes again.',
      improvement: 'Not estimated.',
      evidence: Evidence.notEstimated,
    ));
  }

  fixes.sort((a, b) {
    final tier = a.tier.index.compareTo(b.tier.index);
    return tier != 0 ? tier : b.targetsImproved.compareTo(a.targetsImproved);
  });
  return fixes;
}
