import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/hotspot.dart';
import 'package:sagap/domain/path_track.dart';

HotspotTest testWith(Map<String, Map<String, int>> readings) => HotspotTest(
      candidates: [
        for (final (i, label) in readings.keys.indexed)
          HotspotCandidate(label: label, point: FloorPoint(i.toDouble(), 0)),
      ],
      readings: readings,
    );

void main() {
  test('AT16: A = [−55, −70], B = [−60, −62] → B wins 1 of 2, +1.5 dB', () {
    final result = compareHotspots(testWith({
      'A': {'Desk': -55, 'TV': -70},
      'B': {'Desk': -60, 'TV': -62},
    }))!;
    expect(result.winner, 'B');
    expect(result.runnerUp, 'A');
    expect(result.winsAtSpots, 1);
    expect(result.spotCount, 2);
    expect(result.meanGainDb, closeTo(1.5, 1e-9));
    expect(result.bestBySpot, {'Desk': 'A', 'TV': 'B'});
    expect(
      result.sentence,
      'Spot B gave the strongest signal at 1 of 2 priority spots '
      '(on average 1.5 dB better than A).',
    );
  });

  test('three candidates: winner compared with the runner-up', () {
    final result = compareHotspots(testWith({
      'A': {'Desk': -70, 'TV': -72},
      'B': {'Desk': -60, 'TV': -61},
      'C': {'Desk': -65, 'TV': -64},
    }))!;
    expect(result.winner, 'B');
    expect(result.runnerUp, 'C');
    expect(result.winsAtSpots, 2);
    expect(result.meanGainDb, closeTo(4, 1e-9));
  });

  test('only spots measured for every candidate are compared', () {
    final result = compareHotspots(testWith({
      'A': {'Desk': -60, 'TV': -50},
      'B': {'Desk': -55},
    }))!;
    expect(result.spotCount, 1);
    expect(result.winner, 'B');
  });

  test('ties go to the earlier candidate', () {
    final result = compareHotspots(testWith({
      'A': {'Desk': -60},
      'B': {'Desk': -60},
    }))!;
    expect(result.winner, 'A');
    expect(result.meanGainDb, 0);
  });

  test('needs 2 candidates with readings and a common spot', () {
    expect(compareHotspots(testWith({'A': {'Desk': -60}, 'B': {}})), isNull);
    expect(compareHotspots(testWith({'A': {'Desk': -60}, 'B': {'TV': -60}})), isNull);
  });

  test('withReading and json round-trip', () {
    var test = const HotspotTest(candidates: [
      HotspotCandidate(label: 'A', point: FloorPoint(1, 2)),
      HotspotCandidate(label: 'B', point: FloorPoint(3.5, 0)),
    ]);
    test = test.withReading('A', 'Desk', -61).withReading('A', 'TV', -70);
    final back = HotspotTest.fromJson(test.toJson());
    expect(back.candidates[1].label, 'B');
    expect(back.candidates[1].point.x, 3.5);
    expect(back.readings, {'A': {'Desk': -61, 'TV': -70}});
  });
}
