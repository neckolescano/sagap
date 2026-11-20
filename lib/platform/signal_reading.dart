import '../core/signal/signal_quality.dart';

/// One reading of the connected Wi-Fi network (SPEC.md §7).
class SignalReading {
  const SignalReading({
    required this.tMs,
    required this.connected,
    this.rssiDbm,
    this.freqMhz,
  });

  /// Parses an event from the `sagap/rssi` channel.
  ///
  /// Throws [FormatException] when required fields are missing or mistyped.
  factory SignalReading.fromChannel(Object? event) {
    if (event is! Map) {
      throw FormatException('Signal event is not a map', event);
    }
    final tMs = event['tMs'];
    final connected = event['connected'];
    final rssi = event['rssi'];
    final freq = event['freqMhz'];
    if (tMs is! int || connected is! bool) {
      throw FormatException('Signal event is missing tMs or connected', event);
    }
    return SignalReading(
      tMs: tMs,
      connected: connected,
      rssiDbm: rssi is int ? rssi : null,
      freqMhz: freq is int ? freq : null,
    );
  }

  /// Monotonic device time in milliseconds.
  final int tMs;
  final bool connected;
  final int? rssiDbm;
  final int? freqMhz;

  /// RSSI when connected and inside the valid range; otherwise null.
  int? get validRssi {
    final rssi = rssiDbm;
    if (!connected || rssi == null || !isValidRssi(rssi)) return null;
    return rssi;
  }
}
