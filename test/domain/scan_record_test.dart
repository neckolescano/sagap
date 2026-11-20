import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/core/format/date_format.dart';
import 'package:sagap/data/scan_repository.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/domain/scan_session.dart';

import '../helpers/fakes.dart';

void main() {
  group('pairWithPoses (AT6)', () {
    test('pairs with the nearest pose within 300 ms', () {
      final samples = pairWithPoses(
        [connectedReading(1000, -60)],
        [trackedPose(650, 1, 1), trackedPose(1250, 2, 3)],
      );
      expect(samples, hasLength(1));
      expect(samples.single.rssiDbm, -60);
      expect(samples.single.xM, 2);
      expect(samples.single.yM, 3);
    });

    test('drops a reading with no pose within 300 ms', () {
      final samples = pairWithPoses(
        [connectedReading(1000, -60)],
        [trackedPose(600, 1, 1), trackedPose(1400, 2, 2)],
      );
      expect(samples, isEmpty);
    });

    test('exactly 300 ms still pairs', () {
      final samples = pairWithPoses(
        [connectedReading(1000, -60)],
        [trackedPose(1300, 4, 5)],
      );
      expect(samples.single.xM, 4);
    });

    test('ignores poses that are not tracking', () {
      final samples = pairWithPoses(
        [connectedReading(1000, -60)],
        [lostPose(1000), trackedPose(1200, 7, 8)],
      );
      expect(samples.single.xM, 7);
    });

    test('drops invalid and disconnected readings', () {
      final samples = pairWithPoses(
        [connectedReading(1000, -127), disconnectedReading(2000)],
        [trackedPose(1000, 0, 0), trackedPose(2000, 0, 0)],
      );
      expect(samples, isEmpty);
    });
  });

  test('unpositionedSamples keeps valid readings without positions', () {
    final samples = unpositionedSamples([
      connectedReading(1000, -60, freqMhz: 2412),
      disconnectedReading(2000),
      connectedReading(3000, -70),
    ]);
    expect([for (final s in samples) s.rssiDbm], [-60, -70]);
    expect(samples.first.freqMhz, 2412);
    expect(samples.every((s) => !s.hasPosition), isTrue);
  });

  test('ScanRecord.medianDbm takes the weaker middle for even counts', () {
    final record = buildScanRecord(
      startedAt: testNow,
      durationMs: 4000,
      mode: ScanMode.signalOnly,
      samples: unpositionedSamples([
        connectedReading(1, -50),
        connectedReading(2, -60),
        connectedReading(3, -70),
        connectedReading(4, -80),
      ]),
    );
    expect(record.medianDbm, -70);
    expect(record.path, isEmpty);
    expect(record.walkedM, isNull);
    expect(record.loopErrorM, isNull);
  });

  test('buildScanRecord takes path, walked and loop error from the track', () {
    var track = const PathTrack.empty();
    track = track.add(trackedPose(0, 0, 0));
    track = track.add(trackedPose(200, 3, 0));
    track = track.add(trackedPose(400, 3, 4));
    final record = buildScanRecord(
      startedAt: testNow,
      durationMs: 1000,
      mode: ScanMode.ar,
      samples: const [],
      track: track,
    );
    expect(record.walkedM, closeTo(7, 1e-9));
    expect(record.loopErrorM, closeTo(5, 1e-9));
    expect(record.path.single, hasLength(3));
  });

  group('ScanSession poses', () {
    test('records tracked poses only while recording', () {
      var s = const ScanSession.idle().addPose(trackedPose(0, 1, 1));
      expect(s.poses, isEmpty);
      s = s.start(testNow);
      expect(s.startedAt, testNow);
      s = s.addPose(trackedPose(100, 1, 1));
      s = s.addPose(lostPose(200));
      s = s.pause().addPose(trackedPose(300, 2, 2));
      expect(s.poses, hasLength(1));
    });
  });

  test('date formatting', () {
    expect(formatDate(DateTime(2026, 1, 5)), '5 Jan 2026');
    expect(formatDateTime(DateTime(2026, 11, 20, 9, 3)), '20 Nov 2026, 09:03');
  });
}
