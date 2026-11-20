import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_loss.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/domain/walls.dart';

const router = FloorPoint(0, 0);
const wallAt5 = Wall.vertical(at: 5, from: -10, to: 10);

/// Readings on a grid, generated from a known model and rounded to whole dBm
/// like real RSSI.
List<StoredSample> generated({
  double p0 = -30,
  double n = 3,
  double wallLoss = 10,
  double step = 0.5,
}) {
  final samples = <StoredSample>[];
  for (var x = 1.5; x <= 9; x += step) {
    for (var y = -3.0; y <= 3; y += 1) {
      final d = math.sqrt(x * x + y * y);
      final rssi = p0 - 10 * n * math.log(d) / math.ln10 - (x > 5 ? wallLoss : 0);
      samples.add(StoredSample(tMs: 0, rssiDbm: rssi.round(), xM: x, yM: y));
    }
  }
  return samples;
}

void main() {
  group('walls', () {
    test('a line crosses a wall only when it passes through it', () {
      expect(wallAt5.crossedBy(router, const FloorPoint(8, 1)), isTrue);
      expect(wallAt5.crossedBy(router, const FloorPoint(4, 1)), isFalse);
      expect(wallAt5.crossedBy(router, const FloorPoint(5, 1)), isFalse, reason: 'touching');
      expect(wallAt5.crossedBy(router, const FloorPoint(8, 40)), isFalse, reason: 'past its end');
    });

    test('rooms → walls; a shared wall counts once', () {
      const layout = HomeLayout(rooms: [
        SketchRoom(id: 1, name: 'A', x: 0, y: 0, width: 3, length: 4),
        SketchRoom(id: 2, name: 'B', x: 3, y: 0, width: 3, length: 4),
      ]);
      final walls = wallsFromRooms(layout);
      // x=0, x=3 (shared), x=6, and y=0, y=4 merged across both rooms.
      expect(walls.where((w) => !w.horizontal).map((w) => w.at).toSet(), {0.0, 3.0, 6.0});
      expect(walls.where((w) => !w.horizontal), hasLength(3));
      final top = walls.where((w) => w.horizontal && w.at == 0).single;
      expect((top.from, top.to), (0.0, 6.0));
      expect(wallsCrossed(walls, const FloorPoint(1, 2), const FloorPoint(5, 2)), hasLength(1));
    });
  });

  test('AT14: recovers P0 −30, n 3 and a 10 dB wall within ±0.5', () {
    final model = fitPathLoss(generated(), router, const [wallAt5])!;
    expect(model.p0, closeTo(-30, 0.5));
    expect(model.exponent, closeTo(3, 0.5));
    expect(model.wallLossDb.single, closeTo(10, 0.5));
    expect(model.predict(router, const FloorPoint(8, 0)), closeTo(-30 - 30 * math.log(8) / math.ln10 - 10, 0.5));
  });

  test('no walls: fits distance only', () {
    final model = fitPathLoss(generated(wallLoss: 0), router, const [])!;
    expect(model.exponent, closeTo(3, 0.2));
    expect(model.wallLossDb, isEmpty);
  });

  test('a wall no reading is behind gets no learned loss', () {
    const far = Wall.vertical(at: 50, from: -1, to: 1);
    final model = fitPathLoss(generated(), router, const [wallAt5, far])!;
    expect(model.wallLossDb[1], 0);
  });

  test('readings within 1 m of the router are ignored', () {
    final near = [
      for (var i = 0; i < 20; i++) const StoredSample(tMs: 0, rssiDbm: -20, xM: 0.5, yM: 0),
    ];
    expect(fitPathLoss(near, router, const []), isNull);
  });

  test('solveLinear solves a small system and rejects a singular one', () {
    expect(solveLinear([[2, 1], [1, 3]], [3, 5]), [closeTo(0.8, 1e-9), closeTo(1.4, 1e-9)]);
    expect(solveLinear([[1, 2], [2, 4]], [1, 2]), isNull);
  });

  group('quality gate', () {
    test('AT15: 40 readings → disabled with a reason', () {
      final check = checkModel(
        generated().take(40).toList(),
        router,
        const [wallAt5],
        minSamples: PathLossSettings.minSamplesAr,
      );
      expect(check.usable, isFalse);
      expect(check.problem, contains('40 of 50'));
    });

    test('clean data passes with a small cross-validated error', () {
      final check = checkModel(
        generated(),
        router,
        const [wallAt5],
        minSamples: PathLossSettings.minSamplesAr,
      );
      expect(check.usable, isTrue);
      expect(check.rmseDb, lessThan(1));
    });

    test('noisy data fails the 8 dB limit', () {
      final rng = math.Random(7);
      final noisy = [
        for (final s in generated())
          StoredSample(tMs: 0, rssiDbm: s.rssiDbm + rng.nextInt(41) - 20, xM: s.xM, yM: s.yM),
      ];
      final check = checkModel(noisy, router, const [wallAt5], minSamples: 50);
      expect(check.usable, isFalse);
      expect(check.problem, contains('off by about'));
    });

    test('readings all at one distance fail as implausible', () {
      final ring = [
        for (var a = 0; a < 60; a++)
          StoredSample(
            tMs: 0,
            rssiDbm: -60,
            xM: 3 * math.cos(a / 10),
            yM: 3 * math.sin(a / 10),
          ),
      ];
      final check = checkModel(ring, router, const [], minSamples: 50);
      expect(check.usable, isFalse);
    });
  });
}
