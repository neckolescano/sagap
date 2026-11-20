import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../domain/heatmap.dart';
import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';
import '../../domain/scan_record.dart';

/// A saved scan that has positions, with its home.
class MappableScan {
  const MappableScan(this.home, this.scan);
  final HomeSummary home;
  final ScanSummary scan;

  // Used as a provider key: equal when it is the same saved scan.
  @override
  bool operator ==(Object other) =>
      other is MappableScan && other.scan.id == scan.id && other.home.id == home.id;

  @override
  int get hashCode => Object.hash(scan.id, home.id);
}

/// Every saved AR or sketch scan, newest first. Signal-only scans have no
/// positions, so they can't be mapped.
final mappableScansProvider = FutureProvider<List<MappableScan>>((ref) async {
  final homes = await ref.watch(homesProvider.future);
  final all = <MappableScan>[];
  for (final home in homes) {
    final scans = await ref.watch(scansForHomeProvider(home.id).future);
    all.addAll([
      for (final s in scans)
        if (s.mode != ScanMode.signalOnly) MappableScan(home, s),
    ]);
  }
  all.sort((a, b) => b.scan.startedAt.compareTo(a.scan.startedAt));
  return all;
}, retry: (_, _) => null);

/// Scan chosen on the Map tab; null = newest.
class SelectedMapScan extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int scanId) => state = scanId;

  void clear() => state = null;
}

final selectedMapScanProvider =
    NotifierProvider<SelectedMapScan, int?>(SelectedMapScan.new);

/// Heatmap plus what to draw on top of it.
class MapData {
  const MapData({
    required this.heatmap,
    required this.layout,
    required this.samples,
    this.noSignalSpots = const [],
  });
  final Heatmap heatmap;
  final HomeLayout layout;
  final List<StoredSample> samples;

  /// Sketch spots with no Wi-Fi connection (out of range).
  final List<FloorPoint> noSignalSpots;
}

/// Builds the heatmap for one scan (SPEC.md §8). Runs on the UI isolate;
/// grids are capped at [HeatmapSettings.maxCells], so this stays small.
final mapDataProvider = FutureProvider.family<MapData, MappableScan>((ref, item) async {
  final repo = ref.watch(scanRepositoryProvider);
  final samples = await repo.samplesForScan(item.scan.id);
  final layout = await repo.layoutForHome(item.home.id);
  final manual = item.scan.mode == ScanMode.manual;
  final noSignal = manual ? await repo.noSignalSpotsForScan(item.scan.id) : const <FloorPoint>[];
  return MapData(
    heatmap: buildHeatmap(
      samples,
      minSamplesMeasured:
          manual ? HeatmapSettings.minSamplesManual : HeatmapSettings.minSamplesAr,
      extraBounds: manual ? [...roomCorners(layout), ...noSignal] : const [],
    ),
    layout: manual ? layout : const HomeLayout(),
    samples: samples,
    noSignalSpots: noSignal,
  );
}, retry: (_, _) => null);
