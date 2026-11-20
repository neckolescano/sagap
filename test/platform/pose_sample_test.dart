import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/platform/ar_bridge.dart';

void main() {
  test('parses a pose event', () {
    final p = PoseSample.fromChannel({
      'tMs': 42,
      'tracking': 'TRACKING',
      'failure': 'NONE',
      'x': 1.5,
      'y': 0.2,
      'z': -3.0,
    });
    expect(p.tMs, 42);
    expect(p.tracking, ArTracking.tracking);
    expect(p.failure, 'NONE');
    expect((p.x, p.y, p.z), (1.5, 0.2, -3.0));
  });

  test('parses paused and stopped states', () {
    Map<String, Object> event(String state) => {
          'tMs': 1,
          'tracking': state,
          'failure': 'INSUFFICIENT_LIGHT',
          'x': 0.0,
          'y': 0.0,
          'z': 0.0,
        };
    expect(PoseSample.fromChannel(event('PAUSED')).tracking, ArTracking.paused);
    expect(PoseSample.fromChannel(event('STOPPED')).tracking, ArTracking.stopped);
  });

  test('rejects malformed events', () {
    expect(() => PoseSample.fromChannel(null), throwsFormatException);
    expect(
      () => PoseSample.fromChannel({'tMs': 1, 'tracking': 'TRACKING'}),
      throwsFormatException,
    );
    expect(
      () => PoseSample.fromChannel({
        'tMs': 1,
        'tracking': 'FLYING',
        'failure': 'NONE',
        'x': 0.0,
        'y': 0.0,
        'z': 0.0,
      }),
      throwsFormatException,
    );
  });
}
