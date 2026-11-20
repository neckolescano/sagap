import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/path_track.dart';

/// Smallest area shown, so a short walk isn't blown up to full size.
const double _minSpanM = 3;

/// Top-down mini-map of the walked path with 1 m grid (S4).
class PathMiniMap extends StatelessWidget {
  const PathMiniMap({super.key, required this.track});

  final PathTrack track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fromStart = track.distanceFromStartM.toStringAsFixed(2);
    final walked = track.walkedM.toStringAsFixed(2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Path map', style: textTheme.titleSmall),
            const SizedBox(height: 10),
            Semantics(
              label: 'Walked path map. $fromStart meters from start, '
                  '$walked meters walked.',
              excludeSemantics: true,
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PathPainter(
                    track: track,
                    grid: scheme.outlineVariant,
                    path: scheme.primary,
                    current: scheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Readout(label: 'From start', value: '$fromStart m')),
                Expanded(child: _Readout(label: 'Walked', value: '$walked m')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.track,
    required this.grid,
    required this.path,
    required this.current,
  });

  final PathTrack track;
  final Color grid;
  final Color path;
  final Color current;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final s in track.segments) ...s];
    var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
    if (points.isNotEmpty) {
      minX = points.map((p) => p.x).reduce(math.min);
      maxX = points.map((p) => p.x).reduce(math.max);
      minY = points.map((p) => p.y).reduce(math.min);
      maxY = points.map((p) => p.y).reduce(math.max);
    }
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final spanM = math.max(_minSpanM, math.max(maxX - minX, maxY - minY) * 1.2);
    final pxPerM = math.min(size.width, size.height) / spanM;
    final origin = size.center(Offset.zero);
    Offset toPx(FloorPoint p) =>
        origin + Offset((p.x - centerX) * pxPerM, (p.y - centerY) * pxPerM);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final firstLineX = ((centerX - size.width / 2 / pxPerM)).ceilToDouble();
    for (var m = firstLineX; ; m++) {
      final x = origin.dx + (m - centerX) * pxPerM;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    final firstLineY = ((centerY - size.height / 2 / pxPerM)).ceilToDouble();
    for (var m = firstLineY; ; m++) {
      final y = origin.dy + (m - centerY) * pxPerM;
      if (y > size.height) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = path
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in track.segments) {
      final p = Path()..moveTo(toPx(segment.first).dx, toPx(segment.first).dy);
      for (final point in segment.skip(1)) {
        final o = toPx(point);
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p, linePaint);
    }

    final start = track.start;
    final now = track.current;
    if (start != null) {
      canvas.drawCircle(toPx(start), 7, Paint()..color = AppColors.excellent);
    }
    if (now != null) {
      canvas.drawCircle(toPx(now), 7, Paint()..color = current);
      canvas.drawCircle(
        toPx(now),
        7,
        Paint()
          ..color = path
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.track != track ||
      old.grid != grid ||
      old.path != path ||
      old.current != current;
}
