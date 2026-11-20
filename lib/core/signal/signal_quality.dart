/// Signal strength in words (SPEC.md §3).
///
/// Thresholds are proposed values, not taken from a source; keep them here
/// so they can be tuned in one place.
enum SignalQuality {
  excellent('Excellent'),
  good('Good'),
  weak('Weak'),
  deadZone('Dead zone');

  const SignalQuality(this.label);

  final String label;
}

/// Lowest RSSI (dBm) still classed as Excellent.
const int excellentMinDbm = -59;

/// Lowest RSSI (dBm) still classed as Good.
const int goodMinDbm = -69;

/// Lowest RSSI (dBm) still classed as Weak. Anything lower is a dead zone.
const int weakMinDbm = -79;

/// Readings outside this range are treated as invalid and dropped.
const int validRssiMinDbm = -100;
const int validRssiMaxDbm = 0;

/// Whether [rssiDbm] is a plausible Wi-Fi reading.
bool isValidRssi(int rssiDbm) =>
    rssiDbm >= validRssiMinDbm && rssiDbm <= validRssiMaxDbm;

/// Classifies [rssiDbm] into a [SignalQuality].
///
/// Throws [ArgumentError] for invalid readings; call [isValidRssi] first
/// when the source may produce them.
SignalQuality signalQualityFor(int rssiDbm) {
  if (!isValidRssi(rssiDbm)) {
    throw ArgumentError.value(
      rssiDbm,
      'rssiDbm',
      'must be between $validRssiMinDbm and $validRssiMaxDbm dBm',
    );
  }
  if (rssiDbm >= excellentMinDbm) return SignalQuality.excellent;
  if (rssiDbm >= goodMinDbm) return SignalQuality.good;
  if (rssiDbm >= weakMinDbm) return SignalQuality.weak;
  return SignalQuality.deadZone;
}
