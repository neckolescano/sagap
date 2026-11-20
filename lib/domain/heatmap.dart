import 'dart:math' as math;

import 'home_layout.dart';
import 'path_track.dart';
import 'scan_record.dart';

/// Heatmap settings (SPEC.md §8). All proposals; tune here.
abstract final class HeatmapSettings {
  /// Grid cell size, in meters.
  static const double cellM = 0.5;

  /// Margin around the samples, in meters.
  static const double paddingM = 1;

  /// Samples a cell needs to count as measured during an AR walk.
  static const int minSamplesAr = 3;

  /// A manual spot is already the median of 5 readings, so one is enough.
  static const int minSamplesManual = 1;

  /// IDW: only measured cells within this distance are used.
  static const double idwRadiusM = 5;

  /// IDW: at most this many nearest measured cells are used.
  static const int idwNeighbours = 8;

  /// IDW power (2 = inverse-square).
  static const double idwPower = 2;

  /// Grid size cap; the cell size doubles until the grid fits.
  static const int maxCells = 40000;
}

/// One grid cell's value.
class HeatCell {
  const HeatCell({
    required this.dbm,
    required this.measured,
    required this.sampleCount,
  });

  /// Median (measured) or IDW estimate (predicted), in dBm.
  final double dbm;

  /// True when enough samples fell in this cell; false = predicted.
  final bool measured;

  /// Samples inside this cell (may be > 0 even when predicted).
  final int sampleCount;
}

/// A grid of [HeatCell]s; null cells are not mapped (too far from data).
class Heatmap {
  Heatmap._({
    required this.originX,
    required this.originY,
    required this.cellM,
    required this.cols,
    required this.rows,
    required this.cells,
  });

  /// A grid from explicit cells (row-major), for tests and fixtures.
  factory Heatmap.fromCells({
    required int cols,
    required List<HeatCell?> cells,
    double originX = 0,
    double originY = 0,
    double cellM = HeatmapSettings.cellM,
  }) {
    if (cols <= 0 || cells.length % cols != 0) {
      throw ArgumentError('cells must fill whole rows of $cols');
    }
    return Heatmap._(
      originX: originX,
      originY: originY,
      cellM: cellM,
      cols: cols,
      rows: cells.length ~/ cols,
      cells: cells,
    );
  }

  final double originX;
  final double originY;
  final double cellM;
  final int cols;
  final int rows;

  /// Row-major, `cells[row * cols + col]`.
  final List<HeatCell?> cells;

  bool get isEmpty => cols == 0 || rows == 0;

  HeatCell? cell(int col, int row) => cells[row * cols + col];

  /// The cell containing [p], or null outside the grid or unmapped.
  HeatCell? cellAt(FloorPoint p) {
    final col = ((p.x - originX) / cellM).floor();
    final row = ((p.y - originY) / cellM).floor();
    if (col < 0 || row < 0 || col >= cols || row >= rows) return null;
    return cell(col, row);
  }

  /// Top-left corner of a cell, in meters.
  FloorPoint cellOrigin(int col, int row) =>
      FloorPoint(originX + col * cellM, originY + row * cellM);

  int get measuredCount => cells.where((c) => c?.measured ?? false).length;
  int get predictedCount => cells.where((c) => c != null && !c.measured).length;
}

/// Builds the heatmap from positioned [samples] (SPEC.md §8, AT10).
///
/// 1. Grid over the samples (and [extraBounds], e.g. sketched rooms) + padding.
/// 2. Each cell's samples → median; measured when ≥ [minSamplesMeasured].
/// 3. Other cells → IDW from the nearest measured cells within the radius;
///    no measured cell in range → unmapped (null).
Heatmap buildHeatmap(
  List<StoredSample> samples, {
  required int minSamplesMeasured,
  Iterable<FloorPoint> extraBounds = const [],
  double cellM = HeatmapSettings.cellM,
}) {
  final positioned = [for (final s in samples) if (s.hasPosition) s];
  final points = [
    for (final s in positioned) FloorPoint(s.xM!, s.yM!),
    ...extraBounds,
  ];
  if (positioned.isEmpty) {
    return Heatmap._(originX: 0, originY: 0, cellM: cellM, cols: 0, rows: 0, cells: const []);
  }

  final minX = points.map((p) => p.x).reduce(math.min) - HeatmapSettings.paddingM;
  final minY = points.map((p) => p.y).reduce(math.min) - HeatmapSettings.paddingM;
  final maxX = points.map((p) => p.x).reduce(math.max) + HeatmapSettings.paddingM;
  final maxY = points.map((p) => p.y).reduce(math.max) + HeatmapSettings.paddingM;

  // Grid aligned to multiples of the cell size; grow cells if too many.
  var size = cellM;
  double alignedOrigin(double v, double s) => (v / s).floor() * s;
  int countFor(double min, double max, double s) =>
      math.max(1, ((max - alignedOrigin(min, s)) / s).ceil());
  while (countFor(minX, maxX, size) * countFor(minY, maxY, size) >
      HeatmapSettings.maxCells) {
    size *= 2;
  }
  final originX = alignedOrigin(minX, size);
  final originY = alignedOrigin(minY, size);
  final c = countFor(minX, maxX, size);
  final r = countFor(minY, maxY, size);

  // Step 2: bucket samples per cell.
  final buckets = <int, List<int>>{};
  for (final s in positioned) {
    final col = ((s.xM! - originX) / size).floor();
    final row = ((s.yM! - originY) / size).floor();
    buckets.putIfAbsent(row * c + col, () => []).add(s.rssiDbm);
  }

  final cells = List<HeatCell?>.filled(c * r, null);
  final measured = <(int col, int row, double dbm)>[];
  buckets.forEach((index, values) {
    final isMeasured = values.length >= minSamplesMeasured;
    final median = medianDbm(values).toDouble();
    if (isMeasured) {
      cells[index] = HeatCell(dbm: median, measured: true, sampleCount: values.length);
      measured.add((index % c, index ~/ c, median));
    }
  });

  // Step 3: IDW for every other cell.
  final radiusCells = HeatmapSettings.idwRadiusM / size;
  for (var row = 0; row < r; row++) {
    for (var col = 0; col < c; col++) {
      final index = row * c + col;
      if (cells[index] != null) continue;
      final near = <(double dist, double dbm)>[];
      for (final (mc, mr, dbm) in measured) {
        final d = math.sqrt(math.pow(mc - col, 2) + math.pow(mr - row, 2));
        if (d <= radiusCells) near.add((d * size, dbm));
      }
      if (near.isEmpty) continue;
      near.sort((a, b) => a.$1.compareTo(b.$1));
      var weighted = 0.0;
      var weights = 0.0;
      for (final (dist, dbm) in near.take(HeatmapSettings.idwNeighbours)) {
        final w = 1 / math.pow(dist, HeatmapSettings.idwPower);
        weighted += w * dbm;
        weights += w;
      }
      cells[index] = HeatCell(
        dbm: weighted / weights,
        measured: false,
        sampleCount: buckets[index]?.length ?? 0,
      );
    }
  }

  return Heatmap._(originX: originX, originY: originY, cellM: size, cols: c, rows: r, cells: cells);
}

/// Corners of the sketched rooms, so the heatmap covers the whole sketch.
List<FloorPoint> roomCorners(HomeLayout layout) => [
      for (final room in layout.rooms) ...[
        FloorPoint(room.x, room.y),
        FloorPoint(room.x + room.width, room.y + room.length),
      ],
    ];
