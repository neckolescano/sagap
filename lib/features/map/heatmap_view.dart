import 'package:flutter/material.dart';

import '../../core/signal/signal_quality.dart';
import '../../core/theme/signal_pattern.dart';
import '../../domain/heatmap.dart';
import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';
import '../sketch/sketch_canvas.dart';

/// Opacity of predicted cells; measured cells are drawn solid (SPEC.md §8).
const double predictedOpacity = 0.45;

const double _pinSize = 36;

/// Heatmap with rooms, router and spots on top. Tap a cell to inspect it.
class HeatmapView extends StatelessWidget {
  const HeatmapView({
    super.key,
    required this.heatmap,
    required this.layout,
    this.selected,
    this.onTapPoint,
    this.onDragPoint,
    this.pins = const [],
  });

  /// Called with the finger's position in meters while dragging.
  final ValueChanged<FloorPoint>? onDragPoint;

  final Heatmap heatmap;
  final HomeLayout layout;
  final FloorPoint? selected;

  /// Fix locations (extender / mesh node spots).
  final List<FloorPoint> pins;
  final ValueChanged<FloorPoint>? onTapPoint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final corners = [
        FloorPoint(heatmap.originX, heatmap.originY),
        FloorPoint(
          heatmap.originX + heatmap.cols * heatmap.cellM,
          heatmap.originY + heatmap.rows * heatmap.cellM,
        ),
      ];
      final transform = SketchTransform.fit(layout, size, extra: corners);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTapPoint == null
            ? null
            : (d) => onTapPoint!(transform.toMeters(d.localPosition)),
        onPanStart: onDragPoint == null
            ? null
            : (d) => onDragPoint!(transform.toMeters(d.localPosition)),
        onPanUpdate: onDragPoint == null
            ? null
            : (d) => onDragPoint!(transform.toMeters(d.localPosition)),
        child: Stack(
          children: [
            CustomPaint(
              size: size,
              painter: _HeatmapPainter(
                heatmap: heatmap,
                transform: transform,
                selected: selected,
                selectedColor: scheme.onSurface,
              ),
            ),
            for (final pin in pins)
              Positioned(
                left: transform.toPx(pin).dx - _pinSize / 2,
                top: transform.toPx(pin).dy - _pinSize,
                child: Icon(
                  Icons.location_on,
                  size: _pinSize,
                  color: scheme.primary,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
            // Rooms, router and spots on top, without their own gestures.
            IgnorePointer(
              child: Opacity(
                opacity: 0.9,
                child: SketchCanvas(
                  layout: layout,
                  transparentRooms: true,
                  fixedTransform: transform,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.heatmap,
    required this.transform,
    required this.selected,
    required this.selectedColor,
  });

  final Heatmap heatmap;
  final SketchTransform transform;
  final FloorPoint? selected;
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (var row = 0; row < heatmap.rows; row++) {
      for (var col = 0; col < heatmap.cols; col++) {
        final cell = heatmap.cell(col, row);
        if (cell == null) continue;
        final rect = _rect(col, row);
        canvas.save();
        canvas.translate(rect.left, rect.top);
        SignalPatternPainter(
          signalQualityFor(cell.dbm.round().clamp(validRssiMinDbm, validRssiMaxDbm)),
          inkColor: patternInk,
          opacity: cell.measured ? 1 : predictedOpacity,
        ).paint(canvas, rect.size);
        canvas.restore();
      }
    }
    final s = selected;
    if (s != null) {
      final col = ((s.x - heatmap.originX) / heatmap.cellM).floor();
      final row = ((s.y - heatmap.originY) / heatmap.cellM).floor();
      if (col >= 0 && row >= 0 && col < heatmap.cols && row < heatmap.rows) {
        canvas.drawRect(
          _rect(col, row).inflate(1),
          Paint()
            ..color = selectedColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
  }

  Rect _rect(int col, int row) {
    final o = heatmap.cellOrigin(col, row);
    return Rect.fromPoints(
      transform.toPx(o),
      transform.toPx(FloorPoint(o.x + heatmap.cellM, o.y + heatmap.cellM)),
    );
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.heatmap != heatmap ||
      old.selected != selected ||
      old.transform != transform ||
      old.selectedColor != selectedColor;
}
