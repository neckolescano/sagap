import 'fixes.dart';
import 'path_track.dart';

/// Candidate router spots per hotspot test (SPEC.md §9C: 2–3).
const int minHotspotCandidates = 2;
const int maxHotspotCandidates = 3;

/// Labels given to candidates in order.
const List<String> hotspotLabels = ['A', 'B', 'C'];

/// A place the laptop hotspot is put, standing in for the router.
class HotspotCandidate {
  const HotspotCandidate({required this.label, required this.point});

  final String label;
  final FloorPoint point;
}

/// A laptop-hotspot comparison (SPEC.md §9C). Immutable.
class HotspotTest {
  const HotspotTest({required this.candidates, this.readings = const {}});

  final List<HotspotCandidate> candidates;

  /// Candidate label → priority spot label → median dBm.
  final Map<String, Map<String, int>> readings;

  HotspotTest withReading(String candidate, String spot, int dbm) => HotspotTest(
        candidates: candidates,
        readings: {
          ...readings,
          candidate: {...?readings[candidate], spot: dbm},
        },
      );

  Map<String, Object> toJson() => {
        'candidates': [
          for (final c in candidates) {'label': c.label, 'x': c.point.x, 'y': c.point.y},
        ],
        'readings': readings,
      };

  factory HotspotTest.fromJson(Map<String, Object?> json) {
    final candidates = json['candidates'];
    final readings = json['readings'];
    if (candidates is! List || readings is! Map) {
      throw FormatException('Malformed hotspot test', json);
    }
    return HotspotTest(
      candidates: [
        for (final c in candidates.cast<Map<String, Object?>>())
          HotspotCandidate(
            label: c['label']! as String,
            point: FloorPoint((c['x']! as num).toDouble(), (c['y']! as num).toDouble()),
          ),
      ],
      readings: {
        for (final MapEntry(:key, :value) in readings.entries)
          key as String: {
            for (final MapEntry(key: spot, value: dbm) in (value as Map).entries)
              spot as String: dbm as int,
          },
      },
    );
  }
}

/// The comparison outcome: who won, where, and by how much.
class HotspotResult {
  const HotspotResult({
    required this.winner,
    required this.runnerUp,
    required this.winsAtSpots,
    required this.spotCount,
    required this.meanGainDb,
    required this.bestBySpot,
  });

  final String winner;
  final String runnerUp;

  /// Priority spots where the winner had the strongest signal.
  final int winsAtSpots;

  /// Priority spots measured for every candidate.
  final int spotCount;

  /// Mean of (winner − runner-up) over those spots, in dB.
  final double meanGainDb;

  /// Spot label → candidate label with the strongest reading there.
  final Map<String, String> bestBySpot;

  /// "B gave the strongest signal at 1 of 2 priority spots (on average 1.5 dB
  /// better than A)."
  String get sentence {
    final gain = meanGainDb.abs().toStringAsFixed(1);
    final direction = meanGainDb >= 0 ? 'better' : 'worse';
    return 'Spot $winner gave the strongest signal at $winsAtSpots of $spotCount '
        'priority ${spotCount == 1 ? 'spot' : 'spots'} '
        '(on average $gain dB $direction than $runnerUp).';
  }
}

/// Result card for the Fixes screen (Free, Measured relative). [showPin] is
/// false for AR scans, whose coordinates differ from the sketch.
Fix? hotspotFix(HotspotTest test, String dateLabel, {required bool showPin}) {
  final result = compareHotspots(test);
  if (result == null) return null;
  final winner = test.candidates.firstWhere((c) => c.label == result.winner);
  return Fix(
    kind: FixKind.hotspotResult,
    tier: CostTier.free,
    what: 'Router spot ${result.winner} tested best',
    where: 'Laptop hotspot test, $dateLabel. ${result.sentence}',
    improvement: 'Measured relative to the other spots only; a laptop hotspot '
        'is weaker than a router. Moving the router there is free.',
    evidence: Evidence.measuredRelative,
    points: showPin ? [winner.point] : const [],
    targetsImproved: result.winsAtSpots,
  );
}

/// Compares candidates relative to each other only (SPEC.md §9C, AT16).
///
/// Uses the priority spots measured for every candidate. Each candidate's
/// score is the mean, over those spots, of its reading minus the best reading
/// at that spot (0 = best everywhere). Highest score wins; ties go to the
/// earlier candidate. Returns null with fewer than 2 complete candidates or
/// no common spot.
HotspotResult? compareHotspots(HotspotTest test) {
  final complete = [
    for (final c in test.candidates)
      if (test.readings[c.label]?.isNotEmpty ?? false) c.label,
  ];
  if (complete.length < minHotspotCandidates) return null;
  final spots = test.readings[complete.first]!.keys
      .where((s) => complete.every((c) => test.readings[c]!.containsKey(s)))
      .toList();
  if (spots.isEmpty) return null;

  final best = {
    for (final s in spots)
      s: complete
          .map((c) => test.readings[c]![s]!)
          .reduce((a, b) => a > b ? a : b),
  };
  final score = {
    for (final c in complete)
      c: spots.map((s) => test.readings[c]![s]! - best[s]!).reduce((a, b) => a + b) /
          spots.length,
  };
  final ranked = [...complete]..sort((a, b) {
      final byScore = score[b]!.compareTo(score[a]!);
      return byScore != 0 ? byScore : complete.indexOf(a).compareTo(complete.indexOf(b));
    });
  final winner = ranked[0];
  final runnerUp = ranked[1];
  final bestBySpot = {
    for (final s in spots)
      s: complete.firstWhere((c) => test.readings[c]![s] == best[s]),
  };
  final gain = spots
          .map((s) => test.readings[winner]![s]! - test.readings[runnerUp]![s]!)
          .reduce((a, b) => a + b) /
      spots.length;
  return HotspotResult(
    winner: winner,
    runnerUp: runnerUp,
    winsAtSpots: bestBySpot.values.where((c) => c == winner).length,
    spotCount: spots.length,
    meanGainDb: gain,
    bestBySpot: bestBySpot,
  );
}
