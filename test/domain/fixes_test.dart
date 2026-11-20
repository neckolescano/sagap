import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/channel_check.dart';
import 'package:sagap/domain/fixes.dart';
import 'package:sagap/domain/heatmap.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

StoredSample at(double x, double y, int rssi) =>
    StoredSample(tMs: 0, rssiDbm: rssi, xM: x, yM: y);

/// Manual-style map: each sample is its own measured cell.
Heatmap mapOf(List<StoredSample> samples) =>
    buildHeatmap(samples, minSamplesMeasured: 1);

/// A row of measured cells at y = 0.25 from x = 0.25, one per value.
List<StoredSample> row(List<int> dbm, {double y = 0.25}) =>
    [for (final (i, v) in dbm.indexed) at(0.25 + i * 0.5, y, v)];

void main() {
  group('findDeadZones', () {
    HeatCell c(double dbm) => HeatCell(dbm: dbm, measured: true, sampleCount: 1);

    test('4 connected dead cells form a zone with area and centroid', () {
      final map = Heatmap.fromCells(cols: 6, cells: [
        c(-50), c(-50), c(-90), c(-90), c(-90), c(-90),
      ]);
      final zone = findDeadZones(map).single;
      expect(zone.cells, hasLength(4));
      expect(zone.areaM2, closeTo(1.0, 1e-9));
      expect(zone.centroid.x, closeTo(2.0, 1e-9));
      expect(zone.centroid.y, closeTo(0.25, 1e-9));
    });

    test('3 dead cells are not a zone', () {
      final map = Heatmap.fromCells(cols: 5, cells: [
        c(-50), c(-50), c(-90), c(-90), c(-90),
      ]);
      expect(findDeadZones(map), isEmpty);
    });

    test('diagonal cells are not connected; empty cells break a zone', () {
      final map = Heatmap.fromCells(cols: 4, cells: [
        c(-90), c(-90), null, c(-90),
        c(-50), c(-90), c(-90), c(-50),
        null, c(-50), c(-50), c(-90),
      ]);
      // (0,0)(1,0)(1,1)(2,1) are 4-connected; (3,0) and (3,2) are separate.
      final zones = findDeadZones(map);
      expect(zones.single.cells.toSet(), {(0, 0), (1, 0), (1, 1), (2, 1)});
    });
  });

  group('extenderSpot (9A)', () {
    // Router at x=0.25; −62 at x=2.25 (on the line); dead zone at x≈4.
    final samples = row([-40, -50, -55, -58, -62, -70, -90, -90, -90, -90]);

    test('picks a measured −65…−60 cell on the router → target line', () {
      final map = mapOf(samples);
      final spot = extenderSpot(map, const FloorPoint(0.25, 0.25), const FloorPoint(4.0, 0.25));
      expect(spot, isNotNull);
      expect(spot!.x, closeTo(2.25, 1e-9));
    });

    test('none in band → null', () {
      final map = mapOf(row([-40, -50, -55, -58, -70, -90, -90, -90, -90]));
      expect(extenderSpot(map, const FloorPoint(0.25, 0.25), const FloorPoint(4.0, 0.25)), isNull);
    });

    test('a candidate far off the line is ignored', () {
      final map = mapOf([
        ...row([-40, -50, -70, -90, -90, -90, -90]),
        at(1.25, 3.25, -62),
      ]);
      expect(extenderSpot(map, const FloorPoint(0.25, 0.25), const FloorPoint(3.0, 0.25)), isNull);
    });
  });

  group('buildFixes ranking (AT13, AT17)', () {
    final samples = row([-40, -50, -55, -58, -62, -70, -90, -90, -90, -90]);

    test('Free cards come first, then extender; extender names its spot', () {
      final fixes = buildFixes(
        map: mapOf(samples),
        layout: const HomeLayout(),
        router: const FloorPoint(0.25, 0.25),
        channelChecks: const [],
        channelCheckAvailable: true,
      );
      final tiers = [for (final f in fixes) f.tier.index];
      expect(tiers, orderedEquals([...tiers]..sort()));
      final extender = fixes.firstWhere((f) => f.kind == FixKind.extender);
      expect(extender.what, 'Put a Wi-Fi extender here');
      expect(extender.evidence, Evidence.measured);
      expect(extender.points.single.x, closeTo(2.25, 1e-9));
      expect(extender.improvement, contains('Good'));
    });

    test('no extender spot → "walk again" card instead', () {
      final fixes = buildFixes(
        map: mapOf(row([-40, -50, -55, -58, -70, -90, -90, -90, -90])),
        layout: const HomeLayout(),
        router: const FloorPoint(0.25, 0.25),
        channelChecks: const [],
        channelCheckAvailable: true,
      );
      expect(
        fixes.where((f) => f.kind == FixKind.extender).single.what,
        'Walk the area between the router and the dead zone again',
      );
    });

    test('no targets → no fixes', () {
      final fixes = buildFixes(
        map: mapOf(row([-40, -45, -50, -55])),
        layout: const HomeLayout(),
        router: const FloorPoint(0.25, 0.25),
        channelChecks: const [],
        channelCheckAvailable: true,
      );
      expect(fixes, isEmpty);
    });

    test('no router → asks to mark it', () {
      final fixes = buildFixes(
        map: mapOf(samples),
        layout: const HomeLayout(),
        router: null,
        channelChecks: const [],
        channelCheckAvailable: true,
      );
      expect(fixes.any((f) => f.what == 'Mark your router to get an extender spot'), isTrue);
    });

    test('channel check unavailable → manual channel tip', () {
      final fixes = buildFixes(
        map: mapOf(samples),
        layout: const HomeLayout(),
        router: const FloorPoint(0.25, 0.25),
        channelChecks: const [],
        channelCheckAvailable: false,
      );
      expect(fixes.first.what, 'Check your Wi-Fi channel');
    });

    test('mesh when dead zones lie in opposite directions', () {
      // Router in the middle; dead zones far left and far right.
      final map = mapOf([
        ...row([-90, -90, -90, -90, -62, -50, -40, -50, -62, -90, -90, -90, -90]),
      ]);
      final fixes = buildFixes(
        map: map,
        layout: const HomeLayout(),
        router: const FloorPoint(3.25, 0.25),
        channelChecks: const [],
        channelCheckAvailable: true,
      );
      final mesh = fixes.where((f) => f.kind == FixKind.mesh).single;
      expect(mesh.tier, CostTier.higherCost);
      expect(mesh.points, hasLength(2));
      expect(fixes.last.kind, FixKind.mesh);
    });

    test('priority spot on Weak signal is a target', () {
      const layout = HomeLayout(spots: [
        PrioritySpot(id: 1, label: 'Desk', point: FloorPoint(2.25, 0.25)),
      ]);
      final targets = findTargets(mapOf(row([-50, -60, -70, -72, -74])), layout);
      expect(targets.single.label, 'Desk');
    });
  });

  group('channel advice', () {
    test('crowded channel with a quieter one in the same band', () {
      final advice = adviseChannel(const [
        ChannelCheck(ownFreqMhz: 2437, fresh: true, strongByFreq: {2437: 4, 2412: 1, 2462: 2, 5180: 0}),
      ]);
      expect(advice!.ownChannel, 6);
      expect(advice.betterChannel, 1);
      expect(advice.betterCount, 1);
    });

    test('fewer than 3 neighbours → no advice', () {
      expect(
        adviseChannel(const [
          ChannelCheck(ownFreqMhz: 2437, fresh: true, strongByFreq: {2437: 2, 2412: 0}),
        ]),
        isNull,
      );
    });

    test('channelFor maps the three bands', () {
      expect(channelFor(2412), 1);
      expect(channelFor(2484), 14);
      expect(channelFor(5180), 36);
      expect(channelFor(5955), 1);
      expect(channelFor(900), isNull);
    });

    test('json round-trip', () {
      const check = ChannelCheck(ownFreqMhz: 5180, fresh: false, strongByFreq: {5180: 3, 5200: 1});
      final back = ChannelCheck.fromJson(check.toJson());
      expect(back.ownFreqMhz, 5180);
      expect(back.fresh, isFalse);
      expect(back.strongByFreq, {5180: 3, 5200: 1});
    });
  });

  group('ScanBudget (AT18)', () {
    final t0 = DateTime(2026, 11, 20, 14);

    test('5th request inside 2 minutes is refused', () {
      var budget = const ScanBudget();
      for (var i = 0; i < 4; i++) {
        expect(budget.canScan(t0.add(Duration(seconds: i * 10))), isTrue);
        budget = budget.record(t0.add(Duration(seconds: i * 10)));
      }
      expect(budget.canScan(t0.add(const Duration(seconds: 60))), isFalse);
    });

    test('allowed again once the oldest request is 2 minutes old', () {
      var budget = const ScanBudget();
      for (var i = 0; i < 4; i++) {
        budget = budget.record(t0.add(Duration(seconds: i)));
      }
      expect(budget.canScan(t0.add(const Duration(minutes: 2))), isTrue);
    });
  });
}
