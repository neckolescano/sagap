import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';
import '../../domain/scan_record.dart';
import '../../domain/scan_session.dart';
import '../../platform/signal_source.dart';
import 'scan_controller.dart';

/// Home whose room sketch is used for manual scans; null = not manual mode.
class ManualHome extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int homeId) => state = homeId;

  void clear() => state = null;
}

final manualHomeProvider = NotifierProvider<ManualHome, int?>(ManualHome.new);

/// Spots recorded during a manual scan (S5).
class ManualCapture {
  const ManualCapture({
    this.points = const [],
    this.position,
    this.collecting,
  });

  /// Recorded spots, each the median of [manualReadingsPerSpot] readings.
  final List<StoredSample> points;

  /// Where the user last tapped ("you are here").
  final FloorPoint? position;

  /// Readings gathered for the spot being recorded; null when idle.
  final List<int>? collecting;

  bool get isCollecting => collecting != null;

  List<FloorPoint> get pointLocations =>
      [for (final p in points) FloorPoint(p.xM!, p.yM!)];
}

class ManualCaptureController extends Notifier<ManualCapture> {
  @override
  ManualCapture build() {
    ref.listen(liveSignalProvider, (_, next) {
      final reading = next.value;
      final rssi = reading?.validRssi;
      final gathered = state.collecting;
      final position = state.position;
      final recording = ref.read(scanControllerProvider).status == ScanStatus.recording;
      if (reading == null || rssi == null || gathered == null || position == null || !recording) {
        return;
      }
      final updated = [...gathered, rssi];
      if (updated.length < manualReadingsPerSpot) {
        state = ManualCapture(points: state.points, position: position, collecting: updated);
        return;
      }
      final point = StoredSample(
        tMs: reading.tMs,
        rssiDbm: medianDbm(updated),
        freqMhz: reading.freqMhz,
        xM: position.x,
        yM: position.y,
      );
      state = ManualCapture(points: [...state.points, point], position: position);
    });
    ref.listen(scanControllerProvider.select((s) => s.status), (previous, status) {
      final freshStart = status == ScanStatus.recording && previous != ScanStatus.paused;
      if (freshStart) state = const ManualCapture();
      if (status == ScanStatus.paused) cancel();
    });
    return const ManualCapture();
  }

  /// Sets "you are here". Ignored while a spot is being recorded.
  void setPosition(FloorPoint p) {
    if (state.isCollecting) return;
    state = ManualCapture(points: state.points, position: p);
  }

  /// Starts gathering readings at the current position.
  void recordHere() {
    if (state.position == null || state.isCollecting) return;
    state = ManualCapture(points: state.points, position: state.position, collecting: const []);
  }

  void cancel() =>
      state = ManualCapture(points: state.points, position: state.position);

  void undoLast() {
    if (state.points.isEmpty || state.isCollecting) return;
    state = ManualCapture(
      points: state.points.sublist(0, state.points.length - 1),
      position: state.position,
    );
  }
}

final manualCaptureProvider =
    NotifierProvider<ManualCaptureController, ManualCapture>(ManualCaptureController.new);
