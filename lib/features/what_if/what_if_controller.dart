import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/path_loss.dart';
import '../../domain/path_track.dart';
import '../../domain/scan_record.dart';
import '../../domain/walls.dart';
import '../map/map_controller.dart';

/// Everything the what-if screen needs for one scan.
class WhatIfData {
  const WhatIfData({
    required this.map,
    required this.check,
    required this.router,
    required this.routerGuessed,
  });

  final MapData map;

  /// Null when there is no router position to model from.
  final ModelCheck? check;
  final FloorPoint? router;

  /// True when the router position is where an AR walk started.
  final bool routerGuessed;
}

/// Router position for a scan: the sketched router for sketch scans; for AR
/// walks, the first positioned reading (the guide says to start at the
/// router). The two coordinate systems are never mixed.
(FloorPoint?, bool guessed) routerFor(MappableScan item, MapData data) {
  if (data.layout.router case final r?) return (r, false);
  if (item.scan.mode != ScanMode.ar) return (null, false);
  final positioned = [for (final s in data.samples) if (s.hasPosition) s]
    ..sort((a, b) => a.tMs.compareTo(b.tMs));
  if (positioned.isEmpty) return (null, false);
  return (FloorPoint(positioned.first.xM!, positioned.first.yM!), true);
}

/// Fits and checks the path-loss model for a scan (SPEC.md §9B).
final whatIfProvider = FutureProvider.family<WhatIfData, MappableScan>((ref, item) async {
  final data = await ref.watch(mapDataProvider(item).future);
  final (router, guessed) = routerFor(item, data);
  final check = router == null
      ? null
      : checkModel(
          data.samples,
          router,
          wallsFromRooms(data.layout),
          minSamples: item.scan.mode == ScanMode.manual
              ? PathLossSettings.minSamplesManual
              : PathLossSettings.minSamplesAr,
        );
  return WhatIfData(map: data, check: check, router: router, routerGuessed: guessed);
}, retry: (_, _) => null);
