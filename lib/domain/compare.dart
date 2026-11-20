import '../core/signal/signal_quality.dart';
import 'fixes.dart';
import 'heatmap.dart';
import 'home_layout.dart';
import 'path_track.dart';
import 'scan_record.dart';

/// Changes smaller than this are within normal Wi-Fi variation, so they
/// read "About the same" (SPEC.md §9, before/after).
const int noticeableChangeDb = 3;

/// Change from the walk before a fix to the walk after it.
enum ChangeVerdict { better, same, worse, unknown }

/// One room or priority spot, before and after.
class PlaceChange {
  const PlaceChange({
    required this.name,
    required this.beforeDbm,
    required this.afterDbm,
    this.predicted = false,
  });

  final String name;

  /// Null when this walk has no value for the place.
  final int? beforeDbm;
  final int? afterDbm;

  /// True when either value came from a predicted (not measured) cell.
  final bool predicted;

  int? get deltaDb => switch ((beforeDbm, afterDbm)) {
        (final b?, final a?) => a - b,
        _ => null,
      };

  ChangeVerdict get verdict => switch (deltaDb) {
        null => ChangeVerdict.unknown,
        final d when d >= noticeableChangeDb => ChangeVerdict.better,
        final d when d <= -noticeableChangeDb => ChangeVerdict.worse,
        _ => ChangeVerdict.same,
      };
}

/// One saved sketch walk, ready to compare.
class WalkData {
  const WalkData({
    required this.heatmap,
    required this.samples,
    this.noSignalSpots = const [],
  });

  final Heatmap heatmap;
  final List<StoredSample> samples;
  final List<FloorPoint> noSignalSpots;
}

/// Before/after result for two sketch walks of the same home.
class ScanComparison {
  const ScanComparison({
    required this.overall,
    required this.deadAreaBeforeM2,
    required this.deadAreaAfterM2,
    required this.noSignalBefore,
    required this.noSignalAfter,
    required this.rooms,
    required this.spots,
  });

  /// Median of all measured spots in each walk.
  final PlaceChange overall;
  final double deadAreaBeforeM2;
  final double deadAreaAfterM2;
  final int noSignalBefore;
  final int noSignalAfter;

  /// Home rooms, from the spots recorded inside each one.
  final List<PlaceChange> rooms;

  /// Priority spots, from each walk's heatmap at that point.
  final List<PlaceChange> spots;
}

/// Median of [values], the weaker middle value for an even count; null
/// when empty.
int? _median(List<int> values) => values.isEmpty ? null : medianDbm(values);

int? _cellDbm(Heatmap map, FloorPoint p) =>
    map.cellAt(p)?.dbm.round().clamp(validRssiMinDbm, validRssiMaxDbm);

/// Compares two sketch walks drawn on the same [layout] (SPEC.md §9).
///
/// Rooms use the median of the spots recorded inside them, so walking the
/// same spots each time gives the fairest result. Outside rooms are left
/// out. Values are measured changes; Sagap never claims it raised them.
ScanComparison compareWalks({
  required WalkData before,
  required WalkData after,
  required HomeLayout layout,
}) {
  List<int> inRoom(WalkData walk, SketchRoom room) => [
        for (final s in walk.samples)
          if (s.hasPosition && room.contains(FloorPoint(s.xM!, s.yM!))) s.rssiDbm,
      ];

  return ScanComparison(
    overall: PlaceChange(
      name: 'Whole home',
      beforeDbm: _median([for (final s in before.samples) s.rssiDbm]),
      afterDbm: _median([for (final s in after.samples) s.rssiDbm]),
    ),
    deadAreaBeforeM2: homeDeadAreaM2(before.heatmap, layout),
    deadAreaAfterM2: homeDeadAreaM2(after.heatmap, layout),
    noSignalBefore: before.noSignalSpots.length,
    noSignalAfter: after.noSignalSpots.length,
    rooms: [
      for (final room in layout.homeRooms)
        PlaceChange(
          name: room.name,
          beforeDbm: _median(inRoom(before, room)),
          afterDbm: _median(inRoom(after, room)),
        ),
    ],
    spots: [
      for (final spot in layout.spots)
        PlaceChange(
          name: spot.label,
          beforeDbm: _cellDbm(before.heatmap, spot.point),
          afterDbm: _cellDbm(after.heatmap, spot.point),
          predicted: !(before.heatmap.cellAt(spot.point)?.measured ?? true) ||
              !(after.heatmap.cellAt(spot.point)?.measured ?? true),
        ),
    ],
  );
}
