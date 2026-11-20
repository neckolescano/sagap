import '../core/signal/signal_quality.dart';
import '../platform/ar_bridge.dart';
import '../platform/signal_reading.dart';
import 'channel_check.dart';
import 'path_track.dart';

/// How positions were captured for a scan.
enum ScanMode {
  /// ARCore positions.
  ar,

  /// No positions (phone without AR, or camera not allowed).
  signalOnly,

  /// Positions tapped on a hand-drawn room sketch (SPEC.md §10 step 4).
  manual,
}

/// One stored reading. Position is null for signal-only scans.
class StoredSample {
  const StoredSample({
    required this.tMs,
    required this.rssiDbm,
    this.freqMhz,
    this.xM,
    this.yM,
  });

  final int tMs;
  final int rssiDbm;
  final int? freqMhz;
  final double? xM;
  final double? yM;

  bool get hasPosition => xM != null && yM != null;
}

/// A finished scan ready to save.
class ScanRecord {
  const ScanRecord({
    required this.startedAt,
    required this.durationMs,
    required this.mode,
    required this.samples,
    required this.path,
    this.walkedM,
    this.loopErrorM,
    this.channelChecks = const [],
    this.noSignalSpots = const [],
  });

  /// Nearby-network aggregates from Start and Finish (may be empty).
  final List<ChannelCheck> channelChecks;

  /// Sketch spots where the phone had no connection to the Wi-Fi for a
  /// whole recording (out of range). They carry no dBm, so the heatmap,
  /// signal model and median ignore them; the map shows them as markers.
  final List<FloorPoint> noSignalSpots;

  final DateTime startedAt;
  final int durationMs;
  final ScanMode mode;
  final List<StoredSample> samples;

  /// Walked path segments (AR only; empty otherwise).
  final List<List<FloorPoint>> path;
  final double? walkedM;

  /// End-to-start distance, the drift indicator (SPEC.md §7).
  final double? loopErrorM;

  /// Median RSSI, or null without samples; the weaker middle value for an
  /// even count (same rule as ScanSession).
  int? get medianDbm {
    if (samples.isEmpty) return null;
    final sorted = [for (final s in samples) s.rssiDbm]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }
}

/// Saved home with scan stats, for the Homes list.
class HomeSummary {
  const HomeSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.scanCount,
    this.lastScanAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int scanCount;
  final DateTime? lastScanAt;
}

/// Saved scan, for the home detail list.
class ScanSummary {
  const ScanSummary({
    required this.id,
    required this.homeId,
    required this.startedAt,
    required this.durationMs,
    required this.mode,
    required this.sampleCount,
    this.medianDbm,
    this.walkedM,
    this.loopErrorM,
  });

  final int id;
  final int homeId;
  final DateTime startedAt;
  final int durationMs;
  final ScanMode mode;
  final int sampleCount;
  final int? medianDbm;
  final double? walkedM;
  final double? loopErrorM;

  SignalQuality? get typicalQuality =>
      medianDbm == null ? null : signalQualityFor(medianDbm!);
}

/// Longest time between a reading and a pose for them to be paired
/// (SPEC.md §7, AT6).
const int maxPairingGapMs = 300;

/// Pairs each valid reading with the nearest tracked pose within
/// [maxPairingGapMs]. Readings without such a pose are dropped, so no sample
/// is stored with a guessed position.
List<StoredSample> pairWithPoses(
  List<SignalReading> readings,
  List<PoseSample> poses,
) {
  final tracked = [
    for (final p in poses)
      if (p.tracking == ArTracking.tracking) p,
  ];
  final samples = <StoredSample>[];
  for (final reading in readings) {
    final rssi = reading.validRssi;
    if (rssi == null) continue;
    PoseSample? best;
    var bestGap = maxPairingGapMs + 1;
    for (final pose in tracked) {
      final gap = (pose.tMs - reading.tMs).abs();
      if (gap < bestGap) {
        best = pose;
        bestGap = gap;
      }
    }
    if (best == null) continue;
    samples.add(StoredSample(
      tMs: reading.tMs,
      rssiDbm: rssi,
      freqMhz: reading.freqMhz,
      xM: best.x,
      yM: best.z,
    ));
  }
  return samples;
}

/// Samples without positions, for signal-only scans.
List<StoredSample> unpositionedSamples(List<SignalReading> readings) => [
      for (final r in readings)
        if (r.validRssi case final rssi?)
          StoredSample(tMs: r.tMs, rssiDbm: rssi, freqMhz: r.freqMhz),
    ];
