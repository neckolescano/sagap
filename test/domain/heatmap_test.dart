import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/heatmap.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

StoredSample at(double x, double y, int rssi) =>
    StoredSample(tMs: 0, rssiDbm: rssi, xM: x, yM: y);

/// [count] samples of [rssi] at (x, y).
List<StoredSample> cluster(double x, double y, int rssi, {int count = 3}) =>
    [for (var i = 0; i < count; i++) at(x, y, rssi)];

void main() {
  test('AT10: midpoint between −50 and −70 is −60', () {
    final map = buildHeatmap(
      [...cluster(0.1, 0.1, -50), ...cluster(2.1, 0.1, -70)],
      minSamplesMeasured: 3,
    );
    final mid = map.cellAt(const FloorPoint(1.1, 0.1))!;
    expect(mid.measured, isFalse);
    expect(mid.dbm, closeTo(-60, 1e-9));
    expect(map.cellAt(const FloorPoint(0.1, 0.1))!.measured, isTrue);
    expect(map.cellAt(const FloorPoint(0.1, 0.1))!.dbm, -50);
  });

  test('AT10: cells more than 5 m from any measured cell are blank', () {
    final map = buildHeatmap(
      [...cluster(0.1, 0.1, -50), ...cluster(12.1, 0.1, -70)],
      minSamplesMeasured: 3,
    );
    expect(map.cellAt(const FloorPoint(6.1, 0.1)), isNull);
    expect(map.cellAt(const FloorPoint(4.6, 0.1)), isNotNull);
  });

  test('measured cell uses the median, robust to a spike', () {
    final map = buildHeatmap(
      [at(0.1, 0.1, -60), at(0.2, 0.2, -61), at(0.3, 0.3, -95)],
      minSamplesMeasured: 3,
    );
    final cell = map.cellAt(const FloorPoint(0.1, 0.1))!;
    expect(cell.measured, isTrue);
    expect(cell.sampleCount, 3);
    expect(cell.dbm, -61);
  });

  test('fewer than the minimum samples = predicted, not measured', () {
    final map = buildHeatmap(
      [...cluster(0.1, 0.1, -50), at(3.1, 0.1, -80)],
      minSamplesMeasured: 3,
    );
    final sparse = map.cellAt(const FloorPoint(3.1, 0.1))!;
    expect(sparse.measured, isFalse);
    expect(sparse.sampleCount, 1);
    expect(sparse.dbm, -50, reason: 'only one measured cell to interpolate from');
  });

  test('manual spots count as measured with one sample each', () {
    final map = buildHeatmap([at(1.1, 1.1, -64)], minSamplesMeasured: 1);
    expect(map.cellAt(const FloorPoint(1.1, 1.1))!.measured, isTrue);
    expect(map.measuredCount, 1);
  });

  test('unpositioned samples are ignored; none = empty map', () {
    final map = buildHeatmap(
      [const StoredSample(tMs: 0, rssiDbm: -60)],
      minSamplesMeasured: 1,
    );
    expect(map.isEmpty, isTrue);
  });

  test('extra bounds widen the grid to cover sketched rooms', () {
    const layout = HomeLayout(rooms: [
      SketchRoom(id: 1, name: 'A', x: 0, y: 0, width: 8, length: 4),
    ]);
    final map = buildHeatmap(
      [at(1.1, 1.1, -60)],
      minSamplesMeasured: 1,
      extraBounds: roomCorners(layout),
    );
    // 0..8 m plus 1 m padding each side at 0.5 m cells = 20 columns.
    expect(map.cols, 20);
    expect(map.originX, -1);
  });

  test('a huge area grows the cell size to stay under the cap', () {
    final map = buildHeatmap(
      [at(0, 0, -60), at(200, 200, -60)],
      minSamplesMeasured: 1,
    );
    expect(map.cols * map.rows, lessThanOrEqualTo(HeatmapSettings.maxCells));
    expect(map.cellM, greaterThan(HeatmapSettings.cellM));
  });
}
