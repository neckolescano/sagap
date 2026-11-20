import 'package:flutter/material.dart';

import '../../../core/signal/signal_quality.dart';
import '../../../core/theme/app_colors.dart';
import '../../../platform/signal_reading.dart';
import '../scan_controller.dart';
import 'signal_gauge.dart';

/// Last 60 seconds of signal over faint band stripes. Gaps = no reading.
class SignalTimeline extends StatelessWidget {
  const SignalTimeline({super.key, required this.history});

  final List<SignalReading> history;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 60 seconds', style: textTheme.titleSmall),
            const SizedBox(height: 10),
            Semantics(
              label: 'Signal history for the last 60 seconds',
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    values: [for (final r in history) r.validRssi],
                    lineColor: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.values, required this.lineColor});

  final List<int?> values;
  final Color lineColor;

  double _y(num dbm, double height) {
    final clamped = dbm.clamp(gaugeMinDbm, gaugeMaxDbm);
    return height * (gaugeMaxDbm - clamped) / (gaugeMaxDbm - gaugeMinDbm);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final edges = [gaugeMaxDbm, excellentMinDbm, goodMinDbm, weakMinDbm, gaugeMinDbm];
    for (var i = 0; i < SignalQuality.values.length; i++) {
      final top = _y(edges[i], size.height);
      final bottom = _y(edges[i + 1], size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, size.width, bottom).deflate(0.5),
          const Radius.circular(3),
        ),
        Paint()
          ..color = AppColors.forQuality(SignalQuality.values[i])
              .withValues(alpha: 0.14),
      );
    }

    if (values.isEmpty) return;
    final step = size.width / (signalHistoryLength - 1);
    final offset = signalHistoryLength - values.length;
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    Path? path;
    Offset? lastPoint;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final point = Offset((offset + i) * step, _y(v, size.height));
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      lastPoint = point;
    }
    if (path != null) canvas.drawPath(path, line);
    final last = values.last;
    if (lastPoint != null && last != null) {
      canvas.drawCircle(
        lastPoint,
        4,
        Paint()..color = AppColors.forQuality(signalQualityFor(last)),
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.values != values || old.lineColor != lineColor;
}
