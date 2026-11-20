import 'dart:math' as math;

import 'path_track.dart';
import 'scan_record.dart';
import 'walls.dart';

/// Path-loss model settings (SPEC.md §9B). All proposals; tune here.
abstract final class PathLossSettings {
  /// Samples closer than this to the router are not used (SPEC.md §9B).
  static const double minDistanceM = 1;

  /// Ridge strength pulling each wall's loss toward the shared wall loss,
  /// so walls with few readings behind them fall back to the average.
  static const double wallRidge = 2;

  /// Cross-validation folds.
  static const int folds = 5;

  /// Quality gate: max cross-validated error, in dB.
  static const double maxRmseDb = 8;

  /// Quality gate: minimum readings. AR walks log ~1 reading per second.
  static const int minSamplesAr = 50;

  /// Sketch spots are each a 5-reading median, so fewer are needed.
  static const int minSamplesManual = 10;

  /// Plausible path-loss exponent range; outside it the fit is rejected.
  static const double minExponent = 1;
  static const double maxExponent = 6;
}

/// RSSI(p) = P0 − 10·n·log10(d / 1 m) − Σ wall losses crossed (SPEC.md §9B).
class PathLossModel {
  const PathLossModel({
    required this.p0,
    required this.exponent,
    required this.wallLossDb,
    required this.walls,
  });

  /// Signal at 1 m from the router, in dBm.
  final double p0;

  /// Path-loss exponent n.
  final double exponent;

  /// Learned loss per wall (same order as [walls]), in dB, never negative.
  final List<double> wallLossDb;
  final List<Wall> walls;

  double predict(FloorPoint router, FloorPoint at) {
    final d = math.max(router.distanceTo(at), PathLossSettings.minDistanceM);
    var rssi = p0 - 10 * exponent * math.log(d) / math.ln10;
    for (final i in wallsCrossed(walls, router, at)) {
      rssi -= wallLossDb[i];
    }
    return rssi;
  }
}

/// Fits [PathLossModel] by ridge least squares. Returns null when the data
/// cannot determine the model (too few points or all at one distance).
///
/// Unknowns: P0, n, a shared wall loss L, and per-wall offsets δ_w with a
/// ridge penalty on δ_w only; each wall's loss is L + δ_w.
PathLossModel? fitPathLoss(
  List<StoredSample> samples,
  FloorPoint router,
  List<Wall> walls,
) {
  final rows = <(List<double>, double)>[];
  final crossings = <List<int>>[];
  for (final s in samples) {
    if (!s.hasPosition) continue;
    final p = FloorPoint(s.xM!, s.yM!);
    final d = router.distanceTo(p);
    if (d < PathLossSettings.minDistanceM) continue;
    crossings.add(wallsCrossed(walls, router, p));
    rows.add((
      [1.0, -10 * math.log(d) / math.ln10],
      s.rssiDbm.toDouble(),
    ));
  }

  // Only walls that some reading is behind can be learned.
  final used = <int>{for (final c in crossings) ...c}.toList()..sort();
  final hasWalls = used.isNotEmpty;
  final k = 2 + (hasWalls ? 1 + used.length : 0);
  if (rows.length < k + 1) return null;

  final xtx = List.generate(k, (_) => List<double>.filled(k, 0));
  final xty = List<double>.filled(k, 0);
  for (final (i, (base, y)) in rows.indexed) {
    final x = List<double>.filled(k, 0)..setRange(0, 2, base);
    if (hasWalls) {
      x[2] = -crossings[i].length.toDouble();
      for (final w in crossings[i]) {
        x[3 + used.indexOf(w)] = -1;
      }
    }
    for (var a = 0; a < k; a++) {
      xty[a] += x[a] * y;
      for (var b = 0; b < k; b++) {
        xtx[a][b] += x[a] * x[b];
      }
    }
  }
  for (var j = 3; j < k; j++) {
    xtx[j][j] += PathLossSettings.wallRidge;
  }

  final theta = solveLinear(xtx, xty);
  if (theta == null) return null;
  final shared = hasWalls ? theta[2] : 0.0;
  final losses = List<double>.filled(walls.length, 0);
  for (final (j, w) in used.indexed) {
    losses[w] = math.max(0, shared + theta[3 + j]);
  }
  return PathLossModel(
    p0: theta[0],
    exponent: theta[1],
    wallLossDb: losses,
    walls: walls,
  );
}

/// Solves A·x = b by Gaussian elimination with partial pivoting.
/// Returns null for a (near-)singular system.
List<double>? solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [for (var i = 0; i < n; i++) [...a[i], b[i]]];
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-9) return null;
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final f = m[r][col] / m[col][col];
      for (var c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}

/// Result of the quality gate (SPEC.md §9B, AT15).
class ModelCheck {
  const ModelCheck._({this.model, this.rmseDb, required this.sampleCount, this.problem});

  final PathLossModel? model;

  /// Cross-validated error in dB; null when not computed.
  final double? rmseDb;
  final int sampleCount;

  /// Plain-language reason the model can't be used; null when usable.
  final String? problem;

  bool get usable => problem == null;
}

/// Fits the model and checks it: enough readings, plausible exponent, and
/// 5-fold cross-validated error ≤ [PathLossSettings.maxRmseDb].
ModelCheck checkModel(
  List<StoredSample> samples,
  FloorPoint router,
  List<Wall> walls, {
  required int minSamples,
}) {
  final usable = [
    for (final s in samples)
      if (s.hasPosition &&
          router.distanceTo(FloorPoint(s.xM!, s.yM!)) >= PathLossSettings.minDistanceM)
        s,
  ];
  if (usable.length < minSamples) {
    return ModelCheck._(
      sampleCount: usable.length,
      problem: 'Not enough data to predict. Record more spots '
          '(${usable.length} of $minSamples so far).',
    );
  }
  final model = fitPathLoss(usable, router, walls);
  if (model == null ||
      model.exponent < PathLossSettings.minExponent ||
      model.exponent > PathLossSettings.maxExponent) {
    return ModelCheck._(
      sampleCount: usable.length,
      problem: "Your readings don't fit the simple model. Record spots at "
          'more different distances from the router.',
    );
  }

  var squared = 0.0;
  var count = 0;
  for (var fold = 0; fold < PathLossSettings.folds; fold++) {
    final train = <StoredSample>[];
    final test = <StoredSample>[];
    for (final (i, s) in usable.indexed) {
      (i % PathLossSettings.folds == fold ? test : train).add(s);
    }
    final m = fitPathLoss(train, router, walls);
    if (m == null) continue;
    for (final s in test) {
      final e = m.predict(router, FloorPoint(s.xM!, s.yM!)) - s.rssiDbm;
      squared += e * e;
      count++;
    }
  }
  final rmse = count == 0 ? double.infinity : math.sqrt(squared / count);
  if (rmse > PathLossSettings.maxRmseDb) {
    return ModelCheck._(
      model: model,
      rmseDb: rmse,
      sampleCount: usable.length,
      problem: 'Predictions would be off by about ${rmse.round()} dB, too much '
          'to rely on. Record more spots.',
    );
  }
  return ModelCheck._(model: model, rmseDb: rmse, sampleCount: usable.length);
}
