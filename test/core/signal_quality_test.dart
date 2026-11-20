import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/core/signal/signal_quality.dart';

void main() {
  group('signalQualityFor (AT1)', () {
    const cases = <int, SignalQuality>{
      0: SignalQuality.excellent,
      -40: SignalQuality.excellent,
      -59: SignalQuality.excellent,
      -60: SignalQuality.good,
      -69: SignalQuality.good,
      -70: SignalQuality.weak,
      -79: SignalQuality.weak,
      -80: SignalQuality.deadZone,
      -100: SignalQuality.deadZone,
    };

    cases.forEach((rssi, expected) {
      test('$rssi dBm -> ${expected.label}', () {
        expect(signalQualityFor(rssi), expected);
      });
    });

    test('labels are plain words', () {
      expect(
        SignalQuality.values.map((q) => q.label),
        ['Excellent', 'Good', 'Weak', 'Dead zone'],
      );
    });
  });

  group('invalid readings', () {
    for (final rssi in [5, 1, -101, -120]) {
      test('$rssi dBm is invalid', () {
        expect(isValidRssi(rssi), isFalse);
        expect(() => signalQualityFor(rssi), throwsArgumentError);
      });
    }

    test('range edges are valid', () {
      expect(isValidRssi(0), isTrue);
      expect(isValidRssi(-100), isTrue);
    });
  });
}
