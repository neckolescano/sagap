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

/// One recorded sketch spot: a measured sample, or out of range.
class ManualSpot {
  const ManualSpot.measured(StoredSample this.sample) : _point = null;
  const ManualSpot.noSignal(FloorPoint point)
      : sample = null,
        _point = point;

  /// The measured median; null when the phone had no connection.
  final StoredSample? sample;
  final FloorPoint? _point;

  bool get isNoSignal => sample == null;

  FloorPoint get location => switch (sample) {
        final s? => FloorPoint(s.xM!, s.yM!),
        null => _point!,
      };
}

/// Spots recorded during a manual scan (S5).
class ManualCapture {
  const ManualCapture({
    this.spots = const [],
    this.position,
    this.collecting,
  });

  /// Recorded spots in the order they were taken (Undo removes the last).
  final List<ManualSpot> spots;

  /// Where the user last tapped ("you are here").
  final FloorPoint? position;

  /// Readings gathered for the spot being recorded; a null entry means
  /// "not connected". Null when idle.
  final List<int?>? collecting;

  bool get isCollecting => collecting != null;

  /// Measured spots, each the median of its connected readings.
  List<StoredSample> get points => [for (final s in spots) ?s.sample];

  /// Spots where every reading had no connection.
  List<FloorPoint> get noSignalSpots =>
      [for (final s in spots) if (s.isNoSignal) s.location];

  /// Every recorded spot, measured or not, for room coverage.
  List<FloorPoint> get pointLocations => [for (final s in spots) s.location];
}

class ManualCaptureController extends Notifier<ManualCapture> {
  @override
  ManualCapture build() {
    ref.listen(liveSignalProvider, (_, next) {
      final reading = next.value;
      final gathered = state.collecting;
      final position = state.position;
      final recording = ref.read(scanControllerProvider).status == ScanStatus.recording;
      if (reading == null || gathered == null || position == null || !recording) return;
      final updated = [...gathered, reading.validRssi];
      if (updated.length < manualReadingsPerSpot) {
        state = ManualCapture(spots: state.spots, position: position, collecting: updated);
        return;
      }
      // Out of range only if the phone was off the Wi-Fi for the whole
      // recording; otherwise the connected readings give the median.
      final connected = [for (final r in updated) ?r];
      final spot = connected.isEmpty
          ? ManualSpot.noSignal(position)
          : ManualSpot.measured(StoredSample(
              tMs: reading.tMs,
              rssiDbm: medianDbm(connected),
              freqMhz: reading.freqMhz,
              xM: position.x,
              yM: position.y,
            ));
      state = ManualCapture(spots: [...state.spots, spot], position: position);
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
    state = ManualCapture(spots: state.spots, position: p);
  }

  /// Starts gathering readings at the current position, connected or not.
  void recordHere() {
    if (state.position == null || state.isCollecting) return;
    state = ManualCapture(spots: state.spots, position: state.position, collecting: const []);
  }

  void cancel() => state = ManualCapture(spots: state.spots, position: state.position);

  void undoLast() {
    if (state.spots.isEmpty || state.isCollecting) return;
    state = ManualCapture(
      spots: state.spots.sublist(0, state.spots.length - 1),
      position: state.position,
    );
  }
}

final manualCaptureProvider =
    NotifierProvider<ManualCaptureController, ManualCapture>(ManualCaptureController.new);
