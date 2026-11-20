import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/home_layout.dart';
import '../../../domain/path_track.dart';
import '../../../domain/scan_session.dart';
import '../../sketch/sketch_canvas.dart';
import '../../sketch/sketch_controller.dart';
import '../manual_controller.dart';
import '../scan_controller.dart';

/// Manual scan (S5): tap where you are, then record a 5-reading spot.
class ManualScanPanel extends ConsumerWidget {
  const ManualScanPanel({super.key, required this.homeId, required this.connected});

  final int homeId;
  final bool connected;

  static const double _canvasHeight = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(sketchControllerProvider(homeId)).value;
    final capture = ref.watch(manualCaptureProvider);
    final status = ref.watch(scanControllerProvider.select((s) => s.status));
    final controller = ref.read(manualCaptureProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (layout == null) return const SizedBox.shrink();
    // Recording works without a connection too: such a spot is saved as
    // out of range, which is how you find where the Wi-Fi stops.
    final canRecord = status == ScanStatus.recording &&
        capture.position != null &&
        !capture.isCollecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tap where you are, then Record here', style: textTheme.titleSmall),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius / 2),
              child: SizedBox(
                height: _canvasHeight,
                child: SketchCanvas(
                  layout: layout,
                  marker: capture.position,
                  points: [
                    for (final p in capture.points)
                      SketchPoint(FloorPoint(p.xM!, p.yM!), p.rssiDbm),
                  ],
                  noSignalPoints: capture.noSignalSpots,
                  onTap: capture.isCollecting ? null : controller.setPosition,
                  semanticLabel: 'Room sketch. Tap to mark where you are standing.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (capture.collecting case final gathered?)
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        'Hold still… ${gathered.length} of $manualReadingsPerSpot',
                        style: textTheme.titleMedium,
                      ),
                    ),
                  ),
                  TextButton(onPressed: controller.cancel, child: const Text('Cancel')),
                ],
              )
            else
              Row(
                children: [
                  IconButton(
                    tooltip: 'Undo last spot',
                    onPressed: capture.spots.isEmpty ? null : controller.undoLast,
                    icon: const Icon(Icons.undo),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canRecord ? controller.recordHere : null,
                      icon: const Icon(Icons.radio_button_checked),
                      label: const Text('Record here'),
                    ),
                  ),
                ],
              ),
            if (!connected && status == ScanStatus.recording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No Wi-Fi here. Record to mark this spot Out of range.',
                  style: textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _coverage(layout, capture),
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  static String _coverage(HomeLayout layout, ManualCapture capture) {
    final total = capture.spots.length;
    final noSignal = capture.noSignalSpots.length;
    final spots = '${total == 1 ? '1 spot' : '$total spots'}'
        '${noSignal > 0 ? ' ($noSignal out of range)' : ''}';
    final counts = layout.pointsPerRoom(capture.pointLocations);
    final needing = layout.roomsNeedingPoints(capture.pointLocations);
    if (needing.isEmpty) {
      return '$spots recorded. Every room has $minPointsPerRoom or more.';
    }
    final list = [
      for (final r in needing) '${r.name} ${counts[r.id]}/$minPointsPerRoom',
    ].join(', ');
    return '$spots recorded. Still needed: $list';
  }
}
