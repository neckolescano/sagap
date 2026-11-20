import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/core/signal/signal_quality.dart';
import 'package:sagap/domain/scan_session.dart';

import '../helpers/fakes.dart';

void main() {
  final t0 = DateTime(2026, 11, 20, 14, 5);

  test('idle session ignores readings', () {
    final s = const ScanSession.idle().addReading(connectedReading(1000, -50));
    expect(s.samplesDbm, isEmpty);
    expect(s.recordedMs, 0);
  });

  test('records valid readings and time between them', () {
    var s = const ScanSession.idle().start(t0);
    s = s.addReading(connectedReading(1000, -50));
    s = s.addReading(connectedReading(2000, -72));
    s = s.addReading(connectedReading(3000, -85));
    expect(s.samplesDbm, [-50, -72, -85]);
    expect(s.recordedMs, 2000);
    expect(s.weakestDbm, -85);
    expect(s.strongestDbm, -50);
    expect(s.medianDbm, -72);
  });

  test('disconnected and out-of-range readings count time but not samples', () {
    var s = const ScanSession.idle().start(t0);
    s = s.addReading(connectedReading(1000, -60));
    s = s.addReading(disconnectedReading(2000));
    s = s.addReading(connectedReading(3000, -127));
    expect(s.samplesDbm, [-60]);
    expect(s.recordedMs, 2000);
  });

  test('gaps longer than maxCountedGapMs count as maxCountedGapMs', () {
    var s = const ScanSession.idle().start(t0);
    s = s.addReading(connectedReading(1000, -60));
    s = s.addReading(connectedReading(31000, -60));
    expect(s.recordedMs, 2000);
  });

  test('paused time is not counted', () {
    var s = const ScanSession.idle().start(t0);
    s = s.addReading(connectedReading(1000, -60));
    s = s.addReading(connectedReading(2000, -60));
    s = s.pause();
    s = s.addReading(connectedReading(3000, -90));
    s = s.resume();
    s = s.addReading(connectedReading(9000, -61));
    s = s.addReading(connectedReading(10000, -62));
    expect(s.samplesDbm, [-60, -60, -61, -62]);
    expect(s.recordedMs, 2000);
  });

  test('median of an even count takes the weaker middle value', () {
    var s = const ScanSession.idle().start(t0);
    for (final (i, rssi) in [-50, -60, -70, -80].indexed) {
      s = s.addReading(connectedReading(1000 * (i + 1), rssi));
    }
    expect(s.medianDbm, -70);
  });

  test('countsByQuality buckets each sample', () {
    var s = const ScanSession.idle().start(t0);
    for (final (i, rssi) in [-55, -65, -66, -75, -90].indexed) {
      s = s.addReading(connectedReading(1000 * (i + 1), rssi));
    }
    expect(s.countsByQuality, {
      SignalQuality.excellent: 1,
      SignalQuality.good: 2,
      SignalQuality.weak: 1,
      SignalQuality.deadZone: 1,
    });
  });

  test('empty session has no stats', () {
    final s = const ScanSession.idle().start(t0);
    expect(s.weakestDbm, isNull);
    expect(s.medianDbm, isNull);
  });

  test('invalid transitions throw', () {
    const idle = ScanSession.idle();
    expect(idle.pause, throwsStateError);
    expect(idle.resume, throwsStateError);
    expect(idle.finish, throwsStateError);
    final recording = idle.start(t0);
    expect(() => recording.start(t0), throwsStateError);
    expect(recording.resume, throwsStateError);
  });

  test('finished session can start a fresh scan', () {
    var s = const ScanSession.idle().start(t0);
    s = s.addReading(connectedReading(1000, -60)).finish();
    final next = s.start(t0);
    expect(next.status, ScanStatus.recording);
    expect(next.samplesDbm, isEmpty);
  });
}
