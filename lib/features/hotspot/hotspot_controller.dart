import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/home_layout.dart';
import '../../domain/hotspot.dart';
import '../../domain/path_track.dart';
import '../../platform/signal_source.dart';

enum HotspotPhase { setup, run, results }

/// State of one hotspot test (SPEC.md §9C). Immutable.
class HotspotSession {
  const HotspotSession({
    this.phase = HotspotPhase.setup,
    this.test = const HotspotTest(candidates: []),
    this.current = 0,
    this.connected = false,
    this.collectingSpot,
    this.collected = const [],
  });

  final HotspotPhase phase;
  final HotspotTest test;

  /// Index of the candidate being measured.
  final int current;

  /// User confirmed the phone is on the laptop's hotspot for [current].
  final bool connected;

  /// Priority spot being recorded, or null.
  final String? collectingSpot;
  final List<int> collected;

  HotspotCandidate? get currentCandidate =>
      current < test.candidates.length ? test.candidates[current] : null;

  bool get isLast => current >= test.candidates.length - 1;

  HotspotSession copyWith({
    HotspotPhase? phase,
    HotspotTest? test,
    int? current,
    bool? connected,
    String? collectingSpot,
    bool clearCollecting = false,
    List<int>? collected,
  }) =>
      HotspotSession(
        phase: phase ?? this.phase,
        test: test ?? this.test,
        current: current ?? this.current,
        connected: connected ?? this.connected,
        collectingSpot: clearCollecting ? null : (collectingSpot ?? this.collectingSpot),
        collected: collected ?? this.collected,
      );
}

class HotspotController extends Notifier<HotspotSession> {
  @override
  HotspotSession build() {
    ref.listen(liveSignalProvider, (_, next) {
      final rssi = next.value?.validRssi;
      final spot = state.collectingSpot;
      final candidate = state.currentCandidate;
      if (rssi == null || spot == null || candidate == null) return;
      final gathered = [...state.collected, rssi];
      if (gathered.length < manualReadingsPerSpot) {
        state = state.copyWith(collected: gathered);
        return;
      }
      state = state.copyWith(
        test: state.test.withReading(candidate.label, spot, medianDbm(gathered)),
        clearCollecting: true,
        collected: const [],
      );
    });
    return const HotspotSession();
  }

  void addCandidate(FloorPoint p) {
    final candidates = state.test.candidates;
    if (state.phase != HotspotPhase.setup || candidates.length >= maxHotspotCandidates) return;
    state = state.copyWith(
      test: HotspotTest(candidates: [
        ...candidates,
        HotspotCandidate(
          label: hotspotLabels[candidates.length],
          point: FloorPoint(snapToGrid(p.x), snapToGrid(p.y)),
        ),
      ]),
    );
  }

  void removeLastCandidate() {
    final candidates = state.test.candidates;
    if (state.phase != HotspotPhase.setup || candidates.isEmpty) return;
    state = state.copyWith(
      test: HotspotTest(candidates: candidates.sublist(0, candidates.length - 1)),
    );
  }

  void begin() {
    if (state.test.candidates.length < minHotspotCandidates) return;
    state = state.copyWith(phase: HotspotPhase.run, current: 0, connected: false);
  }

  void setConnected(bool value) =>
      state = state.copyWith(connected: value, clearCollecting: true, collected: const []);

  void record(String spot) {
    if (!state.connected || state.collectingSpot != null) return;
    state = state.copyWith(collectingSpot: spot, collected: const []);
  }

  void cancelRecording() =>
      state = state.copyWith(clearCollecting: true, collected: const []);

  /// Next candidate, or the results after the last one.
  void next() {
    state = state.isLast
        ? state.copyWith(phase: HotspotPhase.results, clearCollecting: true)
        : state.copyWith(current: state.current + 1, connected: false, clearCollecting: true);
  }
}

/// Auto-disposed: leaving the screen ends the test.
final hotspotControllerProvider =
    NotifierProvider.autoDispose<HotspotController, HotspotSession>(HotspotController.new);
