import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/core/signal/signal_format.dart';

void main() {
  test('formatDbm uses a typographic minus', () {
    expect(formatDbm(-62), '−62 dBm');
    expect(formatDbm(0), '0 dBm');
  });

  test('bandLabelFor maps Wi-Fi channel frequencies', () {
    expect(bandLabelFor(2412), '2.4 GHz');
    expect(bandLabelFor(5180), '5 GHz');
    expect(bandLabelFor(5955), '6 GHz');
    expect(bandLabelFor(null), isNull);
    expect(bandLabelFor(900), isNull);
  });

  test('formatDuration shows minutes and padded seconds', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(9999), '0:09');
    expect(formatDuration(125000), '2:05');
  });
}
