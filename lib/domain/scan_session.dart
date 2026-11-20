import '../core/signal/signal_quality.dart';
import '../platform/ar_bridge.dart';
import '../platform/signal_reading.dart';

enum ScanStatus { idle, recording, paused, finished }

/// Longest gap between two readings counted as recording time. Larger gaps
/// (app backgrounded, stream hiccup) count as this much only.
const int maxCountedGapMs = 2000;

/// After this much recording, Scan suggests finishing to save battery
/// (SPEC.md §14, camera + Wi-Fi drain).
const Duration longScanNudge = Duration(minutes: 15);

/// Immutable state of one walk-through.
class ScanSession {
  const ScanSession._({
    required this.status,
    required this.readings,
    required this.poses,
    required this.recordedMs,
    required this.lastReadingTMs,
    required this.startedAt,
  });

  const ScanSession.idle()
      : this._(
          status: ScanStatus.idle,
          readings: const [],
          poses: const [],
          recordedMs: 0,
          lastReadingTMs: null,
          startedAt: null,
        );

  final ScanStatus status;

  /// Readings with a valid RSSI, recorded while [ScanStatus.recording].
  final List<SignalReading> readings;

  /// Tracked AR poses recorded while [ScanStatus.recording].
  final List<PoseSample> poses;

  /// Time spent recording, from reading timestamps.
  final int recordedMs;

  /// Timestamp of the previous reading while recording; null when not.
  final int? lastReadingTMs;

  /// Wall-clock start time; null before the first start.
  final DateTime? startedAt;

  List<int> get samplesDbm => [for (final r in readings) r.validRssi!];

  /// True once recording has passed [longScanNudge].
  bool get isLong => recordedMs >= longScanNudge.inMilliseconds;

  ScanSession _copy({
    ScanStatus? status,
    List<SignalReading>? readings,
    List<PoseSample>? poses,
    int? recordedMs,
    required int? lastReadingTMs,
  }) =>
      ScanSession._(
        status: status ?? this.status,
        readings: readings ?? this.readings,
        poses: poses ?? this.poses,
        recordedMs: recordedMs ?? this.recordedMs,
        lastReadingTMs: lastReadingTMs,
        startedAt: startedAt,
      );

  ScanSession start(DateTime at) {
    if (status != ScanStatus.idle && status != ScanStatus.finished) {
      throw StateError('Cannot start a scan while $status');
    }
    return ScanSession._(
      status: ScanStatus.recording,
      readings: const [],
      poses: const [],
      recordedMs: 0,
      lastReadingTMs: null,
      startedAt: at,
    );
  }

  ScanSession pause() {
    if (status != ScanStatus.recording) {
      throw StateError('Cannot pause while $status');
    }
    return _copy(status: ScanStatus.paused, lastReadingTMs: null);
  }

  ScanSession resume() {
    if (status != ScanStatus.paused) {
      throw StateError('Cannot resume while $status');
    }
    return _copy(status: ScanStatus.recording, lastReadingTMs: null);
  }

  ScanSession finish() {
    if (status != ScanStatus.recording && status != ScanStatus.paused) {
      throw StateError('Cannot finish while $status');
    }
    return _copy(status: ScanStatus.finished, lastReadingTMs: null);
  }

  /// Adds [reading] if recording; ignored otherwise.
  ScanSession addReading(SignalReading reading) {
    if (status != ScanStatus.recording) return this;
    final last = lastReadingTMs;
    var recorded = recordedMs;
    if (last != null && reading.tMs > last) {
      final gap = reading.tMs - last;
      recorded += gap > maxCountedGapMs ? maxCountedGapMs : gap;
    }
    return _copy(
      readings: reading.validRssi == null ? readings : [...readings, reading],
      recordedMs: recorded,
      lastReadingTMs: reading.tMs,
    );
  }

  /// Adds a tracked [pose] if recording; ignored otherwise.
  ScanSession addPose(PoseSample pose) {
    if (status != ScanStatus.recording || pose.tracking != ArTracking.tracking) {
      return this;
    }
    return _copy(poses: [...poses, pose], lastReadingTMs: lastReadingTMs);
  }

  int? get weakestDbm => readings.isEmpty
      ? null
      : samplesDbm.reduce((a, b) => a < b ? a : b);

  int? get strongestDbm => readings.isEmpty
      ? null
      : samplesDbm.reduce((a, b) => a > b ? a : b);

  /// Median sample; for an even count, the lower of the two middle values
  /// (the more cautious reading).
  int? get medianDbm {
    if (readings.isEmpty) return null;
    final sorted = samplesDbm..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  Map<SignalQuality, int> get countsByQuality {
    final counts = {for (final q in SignalQuality.values) q: 0};
    for (final rssi in samplesDbm) {
      final quality = signalQualityFor(rssi);
      counts[quality] = counts[quality]! + 1;
    }
    return counts;
  }
}
