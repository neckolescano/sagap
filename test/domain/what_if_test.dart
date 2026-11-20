import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/core/signal/signal_quality.dart';
import 'package:sagap/domain/fixes.dart';
import 'package:sagap/domain/heatmap.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_loss.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/domain/walls.dart';
import 'package:sagap/domain/what_if.dart';

/// One long room 0–12 m × 0–2 m, desk at the far end.
const layout = HomeLayout(
  rooms: [SketchRoom(id: 1, name: 'Hall', x: 0, y: 0, width: 12, length: 2)],
  spots: [PrioritySpot(id: 1, label: 'Desk', point: FloorPoint(11.5, 1))],
);

/// Known model: P0 −30, n 3.5, no walls.
const model = PathLossModel(p0: -30, exponent: 3.5, wallLossDb: [], walls: []);

Heatmap base() => buildHeatmap(
      const [StoredSample(tMs: 0, rssiDbm: -60, xM: 1, yM: 1)],
      minSamplesMeasured: 1,
      extraBounds: [FloorPoint(0, 0), FloorPoint(12, 2)],
    );

void main() {
  test('predictMap covers only cells inside rooms, all predicted', () {
    final map = predictMap(base(), layout, model, const FloorPoint(0.25, 1));
    final mapped = map.cells.whereType<HeatCell>().toList();
    // 12 × 2 m room at 0.5 m cells = 24 × 4 cells.
    expect(mapped, hasLength(96));
    expect(mapped.every((c) => !c.measured), isTrue);
    expect(map.cellAt(const FloorPoint(-0.5, -0.5)), isNull);
  });

  test('router at one end leaves the desk dead; the middle fixes it', () {
    final atEnd = outcomeFor(base(), layout, model, const FloorPoint(0.25, 1));
    final middle = outcomeFor(base(), layout, model, const FloorPoint(6.25, 1));
    // −30 − 35·log10(11.25) ≈ −66.8 dBm, which is Good (−69…−60).
    expect(model.predict(const FloorPoint(0.25, 1), const FloorPoint(11.5, 1)), closeTo(-66.8, 0.1));
    expect(atEnd.spots['Desk'], SignalQuality.good);
    expect(middle.deadAreaM2, lessThanOrEqualTo(atEnd.deadAreaM2));
  });

  test('bestRouterSpot improves on a corner router', () {
    const weak = PathLossModel(p0: -40, exponent: 4, wallLossDb: [], walls: []);
    final current = const FloorPoint(0.25, 0.25);
    final before = outcomeFor(base(), layout, weak, current);
    expect(before.spots['Desk'], isNot(SignalQuality.good));
    final spot = bestRouterSpot(base(), layout, weak, current)!;
    final after = outcomeFor(base(), layout, weak, spot);
    expect(after.goodSpots, greaterThan(before.goodSpots));
    expect(layout.roomAt(spot), isNotNull, reason: 'router stays indoors');
  });

  test('no better spot → null', () {
    const strong = PathLossModel(p0: -20, exponent: 2, wallLossDb: [], walls: []);
    expect(bestRouterSpot(base(), layout, strong, const FloorPoint(6.25, 1)), isNull);
  });

  test('walls reduce the predicted signal behind them', () {
    const wall = Wall.vertical(at: 6, from: 0, to: 2);
    const withWall = PathLossModel(p0: -30, exponent: 3, wallLossDb: [10], walls: [wall]);
    final router = const FloorPoint(1, 1);
    final before = withWall.predict(router, const FloorPoint(5, 1));
    final behind = withWall.predict(router, const FloorPoint(7, 1));
    expect(before - behind, greaterThan(10));
  });

  test('describeChange lists spot and area changes', () {
    const before = RouterOutcome(deadAreaM2: 9, spots: {'Desk': SignalQuality.weak});
    const after = RouterOutcome(deadAreaM2: 3, spots: {'Desk': SignalQuality.good});
    expect(describeChange(before, after), 'Desk Weak → Good; dead zones 9.0 m² → 3.0 m²');
    expect(describeChange(before, before), 'About the same');
  });

  test('moveRouterFix is Free, Predicted, and asks to confirm first', () {
    const weak = PathLossModel(p0: -40, exponent: 4, wallLossDb: [], walls: []);
    final samples = [
      for (var x = 1.0; x <= 11; x += 0.25)
        StoredSample(
          tMs: 0,
          rssiDbm: weak.predict(const FloorPoint(0.25, 0.25), FloorPoint(x, 1)).round(),
          xM: x,
          yM: 1,
        ),
    ];
    final check = checkModel(samples, const FloorPoint(0.25, 0.25), const [], minSamples: 10);
    expect(check.usable, isTrue);
    final fix = moveRouterFix(
      base: base(),
      layout: layout,
      check: check,
      router: const FloorPoint(0.25, 0.25),
    )!;
    expect(fix.tier, CostTier.free);
    expect(fix.evidence, Evidence.predicted);
    expect(fix.where, startsWith('In Hall'));
    expect(fix.improvement, startsWith('Predicted: Desk'));
    expect(fix.improvement, contains('Confirm with the hotspot test'));
  });
}
