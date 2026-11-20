import 'package:flutter/material.dart';

import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_colors.dart';

/// Step 1: a router sending out signal arcs.
class RouterIllustration extends CustomPainter {
  RouterIllustration({required this.accent, required this.ink});

  final Color accent;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.72);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 120, height: 40),
      const Radius.circular(12),
    );
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(body, stroke);
    canvas.drawLine(c + const Offset(-36, -20), c + const Offset(-46, -58), stroke);
    canvas.drawLine(c + const Offset(36, -20), c + const Offset(46, -58), stroke);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(c + Offset(-30.0 + i * 16, 0), 4, Paint()..color = accent);
    }
    final origin = c + const Offset(0, -30);
    for (var i = 1; i <= 3; i++) {
      final r = 34.0 * i + 12;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r),
        3.6,
        2.2,
        false,
        Paint()
          ..color = accent.withValues(alpha: 1 - i * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(RouterIllustration old) =>
      old.accent != accent || old.ink != ink;
}

/// Step 2: room outlines with a walked path coloured by signal.
class WalkIllustration extends CustomPainter {
  WalkIllustration({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = w / 2 - 130;
    final top = h / 2 - 80;
    final walls = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(Rect.fromLTWH(left, top, 260, 160), walls);
    canvas.drawLine(Offset(left + 140, top), Offset(left + 140, top + 60), walls);
    canvas.drawLine(Offset(left + 140, top + 110), Offset(left + 140, top + 160), walls);
    canvas.drawLine(Offset(left + 140, top + 90), Offset(left + 260, top + 90), walls);

    final points = [
      Offset(left + 30, top + 130),
      Offset(left + 60, top + 90),
      Offset(left + 100, top + 60),
      Offset(left + 140, top + 85),
      Offset(left + 180, top + 60),
      Offset(left + 220, top + 40),
      Offset(left + 200, top + 120),
      Offset(left + 235, top + 135),
    ];
    const qualities = [
      SignalQuality.excellent,
      SignalQuality.excellent,
      SignalQuality.good,
      SignalQuality.good,
      SignalQuality.weak,
      SignalQuality.weak,
      SignalQuality.deadZone,
      SignalQuality.deadZone,
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 8, Paint()..color = AppColors.forQuality(qualities[i]));
    }
  }

  @override
  bool shouldRepaint(WalkIllustration old) => old.ink != ink;
}

/// Step 3: fix cards ranked by cost.
class FixesIllustration extends CustomPainter {
  FixesIllustration({required this.card, required this.ink, required this.accent});

  final Color card;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const cardW = 240.0;
    const cardH = 44.0;
    const gap = 14.0;
    final left = size.width / 2 - cardW / 2;
    final top = size.height / 2 - (cardH * 3 + gap * 2) / 2;
    final tags = [accent, AppColors.good, AppColors.weak];
    for (var i = 0; i < 3; i++) {
      final y = top + i * (cardH + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y, cardW, cardH),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, Paint()..color = card);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + 12, y + 14, 16, 16),
          const Radius.circular(4),
        ),
        Paint()..color = tags[i],
      );
      final line = Paint()
        ..color = ink.withValues(alpha: 0.5)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(left + 42, y + 17), Offset(left + 170 - i * 24, y + 17), line);
      canvas.drawLine(
        Offset(left + 42, y + 29),
        Offset(left + 120 - i * 16, y + 29),
        line..color = ink.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(FixesIllustration old) =>
      old.card != card || old.ink != ink || old.accent != accent;
}
