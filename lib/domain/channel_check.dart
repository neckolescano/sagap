/// Nearby-network check for the channel fix (SPEC.md §7, §9D).
///
/// Only aggregates are kept: how many strong neighbours share each
/// frequency. No network names or addresses are stored or sent to Dart.
class ChannelCheck {
  const ChannelCheck({
    required this.ownFreqMhz,
    required this.strongByFreq,
    required this.fresh,
  });

  /// Frequency of the network the phone is connected to.
  final int ownFreqMhz;

  /// Count of other networks stronger than [strongNeighbourDbm], by frequency.
  final Map<int, int> strongByFreq;

  /// False when Android throttled the scan and cached results were used.
  final bool fresh;

  Map<String, Object> toJson() => {
        'own': ownFreqMhz,
        'fresh': fresh,
        'counts': {for (final e in strongByFreq.entries) '${e.key}': e.value},
      };

  factory ChannelCheck.fromJson(Map<String, Object?> json) {
    final own = json['own'];
    final fresh = json['fresh'];
    final counts = json['counts'];
    if (own is! int || fresh is! bool || counts is! Map) {
      throw FormatException('Malformed channel check', json);
    }
    return ChannelCheck(
      ownFreqMhz: own,
      fresh: fresh,
      strongByFreq: {
        for (final e in counts.entries) int.parse(e.key as String): e.value as int,
      },
    );
  }
}

/// Neighbours at or above this level count as strong (SPEC.md §7).
const int strongNeighbourDbm = -70;

/// Strong neighbours on our channel before the channel fix is suggested.
const int crowdedChannelMin = 3;

/// Wi-Fi channel number for a frequency, or null if outside the bands.
int? channelFor(int freqMhz) {
  if (freqMhz == 2484) return 14;
  if (freqMhz >= 2412 && freqMhz <= 2472) return (freqMhz - 2407) ~/ 5;
  if (freqMhz >= 5160 && freqMhz <= 5885) return (freqMhz - 5000) ~/ 5;
  if (freqMhz >= 5955 && freqMhz <= 7115) return (freqMhz - 5950) ~/ 5;
  return null;
}

/// Same Wi-Fi band (2.4 / 5 / 6 GHz).
bool sameBand(int a, int b) {
  int band(int f) => f < 3000 ? 2 : (f < 5925 ? 5 : 6);
  return band(a) == band(b);
}

/// A suggested channel change, when our channel is crowded.
class ChannelAdvice {
  const ChannelAdvice({
    required this.ownChannel,
    required this.ownCount,
    required this.betterChannel,
    required this.betterCount,
  });

  final int ownChannel;
  final int ownCount;
  final int betterChannel;
  final int betterCount;
}

/// Suggests a channel when ≥ [crowdedChannelMin] strong neighbours share
/// ours and another seen channel in the same band has fewer (SPEC.md §9D).
///
/// Only channels where networks were seen are compared, so the suggestion is
/// always a channel that exists in this area.
ChannelAdvice? adviseChannel(List<ChannelCheck> checks) {
  if (checks.isEmpty) return null;
  // Use the most crowded reading of our channel across the checks.
  final latest = checks.last;
  final own = latest.ownFreqMhz;
  final ownChannel = channelFor(own);
  if (ownChannel == null) return null;
  final merged = <int, int>{};
  for (final check in checks) {
    check.strongByFreq.forEach((freq, count) {
      final previous = merged[freq];
      merged[freq] = previous == null || count > previous ? count : previous;
    });
  }
  final ownCount = merged[own] ?? 0;
  if (ownCount < crowdedChannelMin) return null;
  int? bestFreq;
  for (final entry in merged.entries) {
    if (entry.key == own || !sameBand(entry.key, own)) continue;
    if (channelFor(entry.key) == null) continue;
    if (bestFreq == null || entry.value < merged[bestFreq]!) bestFreq = entry.key;
  }
  if (bestFreq == null || merged[bestFreq]! >= ownCount) return null;
  return ChannelAdvice(
    ownChannel: ownChannel,
    ownCount: ownCount,
    betterChannel: channelFor(bestFreq)!,
    betterCount: merged[bestFreq]!,
  );
}

/// Android allows 4 scans per 2 minutes for a foreground app (SPEC.md §7).
const int scanBudgetCount = 4;
const Duration scanBudgetWindow = Duration(minutes: 2);

/// Channel checks per survey: at Start and at Finish (SPEC.md §7).
const int scansPerSurvey = 2;

/// App-side scan counter so the app never asks Android for more than the
/// throttle allows (AT18). Immutable.
class ScanBudget {
  const ScanBudget([this.requests = const []]);

  final List<DateTime> requests;

  bool canScan(DateTime now) =>
      requests.where((t) => now.difference(t) < scanBudgetWindow).length <
      scanBudgetCount;

  ScanBudget record(DateTime now) => ScanBudget([
        for (final t in requests)
          if (now.difference(t) < scanBudgetWindow) t,
        now,
      ]);
}
