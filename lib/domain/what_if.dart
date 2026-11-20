import '../core/signal/signal_quality.dart';
import 'fixes.dart';
import 'heatmap.dart';
import 'home_layout.dart';
import 'path_loss.dart';
import 'path_track.dart';

/// Candidate router spots are tried every this many cells (1 m at 0.5 m cells).
const int _candidateStride = 2;

/// Smallest dead-zone reduction worth suggesting a move for, in m².
const double minDeadAreaGainM2 = 0.5;

/// Predicted signal for every cell in the home, for a router at [router].
///
/// "The home" = cells inside sketched rooms, or, without rooms, the cells the
/// heatmap mapped. Every cell is marked predicted.
Heatmap predictMap(Heatmap base, HomeLayout layout, PathLossModel model, FloorPoint router) {
  final cells = <HeatCell?>[
    for (var row = 0; row < base.rows; row++)
      for (var col = 0; col < base.cols; col++)
        _inHome(base, layout, col, row)
            ? HeatCell(dbm: model.predict(router, _center(base, col, row)), measured: false, sampleCount: 0)
            : null,
  ];
  return Heatmap.fromCells(
    cols: base.cols,
    cells: cells,
    originX: base.originX,
    originY: base.originY,
    cellM: base.cellM,
  );
}

FloorPoint _center(Heatmap map, int col, int row) {
  final o = map.cellOrigin(col, row);
  return FloorPoint(o.x + map.cellM / 2, o.y + map.cellM / 2);
}

bool _inHome(Heatmap base, HomeLayout layout, int col, int row) =>
    layout.rooms.isEmpty
        ? base.cell(col, row) != null
        : layout.roomAt(_center(base, col, row)) != null;

SignalQuality _quality(double dbm) =>
    signalQualityFor(dbm.round().clamp(validRssiMinDbm, validRssiMaxDbm));

/// What a router position would give: dead-zone area and each priority spot.
class RouterOutcome {
  const RouterOutcome({required this.deadAreaM2, required this.spots});

  final double deadAreaM2;

  /// Priority spot label → predicted signal word.
  final Map<String, SignalQuality> spots;

  int get goodSpots => spots.values
      .where((q) => q == SignalQuality.excellent || q == SignalQuality.good)
      .length;
}

RouterOutcome outcomeFor(
  Heatmap base,
  HomeLayout layout,
  PathLossModel model,
  FloorPoint router,
) {
  final predicted = predictMap(base, layout, model, router);
  final dead = predicted.cells
      .where((c) => c != null && _quality(c.dbm) == SignalQuality.deadZone)
      .length;
  return RouterOutcome(
    deadAreaM2: dead * base.cellM * base.cellM,
    spots: {
      for (final s in layout.spots) s.label: _quality(model.predict(router, s.point)),
    },
  );
}

/// The best router spot in the home: most priority spots Good or better,
/// then the least dead-zone area (SPEC.md §9B). Null when no spot beats the
/// current position.
FloorPoint? bestRouterSpot(
  Heatmap base,
  HomeLayout layout,
  PathLossModel model,
  FloorPoint current,
) {
  final now = outcomeFor(base, layout, model, current);
  FloorPoint? best;
  RouterOutcome? bestOutcome;
  for (var row = 0; row < base.rows; row += _candidateStride) {
    for (var col = 0; col < base.cols; col += _candidateStride) {
      if (!_inHome(base, layout, col, row)) continue;
      final spot = _center(base, col, row);
      final o = outcomeFor(base, layout, model, spot);
      if (bestOutcome == null ||
          o.goodSpots > bestOutcome.goodSpots ||
          (o.goodSpots == bestOutcome.goodSpots && o.deadAreaM2 < bestOutcome.deadAreaM2)) {
        best = spot;
        bestOutcome = o;
      }
    }
  }
  if (best == null || bestOutcome == null) return null;
  final better = bestOutcome.goodSpots > now.goodSpots ||
      (bestOutcome.goodSpots == now.goodSpots &&
          now.deadAreaM2 - bestOutcome.deadAreaM2 >= minDeadAreaGainM2);
  return better ? best : null;
}

String _area(double m2) => '${m2.toStringAsFixed(1)} m²';

/// Plain summary of a move: "Desk Weak → Good; dead zones 9.0 m² → 3.0 m²".
String describeChange(RouterOutcome before, RouterOutcome after) {
  final parts = <String>[
    for (final MapEntry(key: label, value: q) in before.spots.entries)
      if (after.spots[label] != q) '$label ${q.label} → ${after.spots[label]!.label}',
    if (before.deadAreaM2 != after.deadAreaM2)
      'dead zones ${_area(before.deadAreaM2)} → ${_area(after.deadAreaM2)}',
  ];
  return parts.isEmpty ? 'About the same' : parts.join('; ');
}

/// "Move the router" card (Free tier, Predicted), or null when no better
/// spot is found.
Fix? moveRouterFix({
  required Heatmap base,
  required HomeLayout layout,
  required ModelCheck check,
  required FloorPoint router,
}) {
  final model = check.model;
  if (!check.usable || model == null) return null;
  final spot = bestRouterSpot(base, layout, model, router);
  if (spot == null) return null;
  final before = outcomeFor(base, layout, model, router);
  final after = outcomeFor(base, layout, model, spot);
  final room = layout.roomAt(spot)?.name;
  final meters = router.distanceTo(spot).toStringAsFixed(1);
  return Fix(
    kind: FixKind.moveRouter,
    tier: CostTier.free,
    what: 'Move the router',
    where: room == null
        ? '$meters m from where it is now'
        : 'In $room, $meters m from where it is now',
    improvement: 'Predicted: ${describeChange(before, after)}. Confirm with the '
        'hotspot test or a re-walk before moving it.',
    evidence: Evidence.predicted,
    points: [spot],
    targetsImproved: after.goodSpots - before.goodSpots +
        (after.deadAreaM2 < before.deadAreaM2 ? 1 : 0),
  );
}
