import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/platform/signal_reading.dart';

void main() {
  test('parses a connected event', () {
    final r = SignalReading.fromChannel({
      'tMs': 1234,
      'connected': true,
      'rssi': -61,
      'freqMhz': 2437,
      'source': 'callback',
    });
    expect(r.tMs, 1234);
    expect(r.connected, isTrue);
    expect(r.rssiDbm, -61);
    expect(r.freqMhz, 2437);
    expect(r.validRssi, -61);
  });

  test('parses a disconnected event without rssi', () {
    final r = SignalReading.fromChannel({'tMs': 5, 'connected': false});
    expect(r.rssiDbm, isNull);
    expect(r.validRssi, isNull);
  });

  test('validRssi is null for out-of-range values', () {
    final r = SignalReading.fromChannel({'tMs': 5, 'connected': true, 'rssi': -127});
    expect(r.validRssi, isNull);
  });

  test('throws FormatException for malformed events', () {
    expect(() => SignalReading.fromChannel('nope'), throwsFormatException);
    expect(() => SignalReading.fromChannel({'connected': true}), throwsFormatException);
    expect(() => SignalReading.fromChannel({'tMs': 1}), throwsFormatException);
  });
}
