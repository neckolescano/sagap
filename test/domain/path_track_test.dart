import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/features/scan/ar_controller.dart';
import 'package:sagap/platform/ar_bridge.dart';

import '../helpers/fakes.dart';

void main() {
  test('5 m straight line: walked and from-start are both 5 m', () {
    var track = const PathTrack.empty();
    for (var i = 0; i <= 10; i++) {
      track = track.add(trackedPose(i * 200, 0, -0.5 * i));
    }
    expect(track.walkedM, closeTo(5.0, 1e-9));
    expect(track.distanceFromStartM, closeTo(5.0, 1e-9));
    expect(track.segments, hasLength(1));
    expect(track.segments.single, hasLength(11));
  });

  test('loop back to start: from-start is the loop-closure error', () {
    var track = const PathTrack.empty();
    final corners = [(0.0, 0.0), (3.0, 0.0), (3.0, 4.0), (0.0, 4.0), (0.1, 0.0)];
    for (final (i, (x, z)) in corners.indexed) {
      track = track.add(trackedPose(i * 1000, x, z));
    }
    expect(track.walkedM, closeTo(3 + 4 + 3 + 4.0012498, 1e-6));
    expect(track.distanceFromStartM, closeTo(0.1, 1e-9));
  });

  test('steps under 5 cm are jitter and ignored', () {
    var track = const PathTrack.empty();
    track = track.add(trackedPose(0, 0, 0));
    track = track.add(trackedPose(200, 0.03, 0));
    track = track.add(trackedPose(400, 0.04, 0));
    expect(track.walkedM, 0);
    expect(track.segments.single, hasLength(1));
  });

  test('tracking loss starts a new segment; the jump is not counted', () {
    var track = const PathTrack.empty();
    track = track.add(trackedPose(0, 0, 0));
    track = track.add(trackedPose(200, 1, 0));
    track = track.add(lostPose(400));
    track = track.add(trackedPose(600, 5, 0));
    track = track.add(trackedPose(800, 6, 0));
    expect(track.segments, hasLength(2));
    expect(track.walkedM, closeTo(2.0, 1e-9));
    expect(track.distanceFromStartM, closeTo(6.0, 1e-9));
  });

  test('poses before tracking starts are ignored', () {
    var track = const PathTrack.empty();
    track = track.add(lostPose(0));
    expect(track.segments, isEmpty);
    expect(track.distanceFromStartM, 0);
  });

  group('trackingMessage', () {
    test('null while tracking', () {
      expect(trackingMessage(trackedPose(0, 0, 0)), isNull);
    });

    const cases = {
      'INSUFFICIENT_LIGHT': 'Too dark. Turn on a light.',
      'INSUFFICIENT_FEATURES': 'Point at a textured area, not a blank wall.',
      'EXCESSIVE_MOTION': 'Move slower.',
      'CAMERA_UNAVAILABLE': 'The camera is unavailable.',
      'BAD_STATE': 'AR stopped. Try Pause, then Resume.',
      'NONE': 'Move the phone slowly to start tracking.',
    };
    cases.forEach((failure, message) {
      test(failure, () {
        expect(trackingMessage(lostPose(0, failure: failure)), message);
      });
    });

    test('stopped state also gets a message', () {
      const pose = PoseSample(
        tMs: 0,
        tracking: ArTracking.stopped,
        failure: 'NONE',
        x: 0,
        y: 0,
        z: 0,
      );
      expect(trackingMessage(pose), 'Move the phone slowly to start tracking.');
    });
  });
}
