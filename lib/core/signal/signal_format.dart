/// Display helpers for signal values. dBm is always secondary to the word.
library;

const String _minus = '−';

/// `-62` → `−62 dBm` (typographic minus).
String formatDbm(int dbm) =>
    dbm < 0 ? '$_minus${-dbm} dBm' : '$dbm dBm';

/// Wi-Fi band for a channel frequency, or null if outside the known bands.
String? bandLabelFor(int? freqMhz) {
  if (freqMhz == null) return null;
  if (freqMhz >= 2400 && freqMhz < 2500) return '2.4 GHz';
  if (freqMhz >= 4900 && freqMhz < 5925) return '5 GHz';
  if (freqMhz >= 5925 && freqMhz <= 7125) return '6 GHz';
  return null;
}

/// `125000` ms → `2:05`.
String formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
