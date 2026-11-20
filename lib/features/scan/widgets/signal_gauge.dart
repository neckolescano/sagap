import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/signal/signal_format.dart';
import '../../../core/signal/signal_quality.dart';
import '../../../core/theme/app_colors.dart';

/// Gauge scale. Readings outside are drawn at the ends.
const int gaugeMinDbm = -100;
const int gaugeMaxDbm = -30;

const double _startAngle = 150 * math.pi / 180;
const double _sweepAngle = 240 * math.pi / 180;

/// Side inset of the gauge text: this share of the gauge width, at most
/// [_maxTextInsetPx], so the text stays inside the ring.
const double _textInsetFraction = 0.2;
const double _maxTextInsetPx = 48;

/// What the gauge shows in its centre.
sealed class GaugeReading {
  const GaugeReading();
}

class GaugeSignal extends GaugeReading {
  const GaugeSignal(this.rssiDbm, {this.bandLabel});
  final int rssiDbm;
  final String? bandLabel;
}

class GaugeMessage extends GaugeReading {
  const GaugeMessage(this.title, this.detail);
  final String title;
  final String detail;
}

/// Large radial signal meter (SPEC.md §11 design direction).
class SignalGauge extends StatelessWidget {
  const SignalGauge({super.key, required this.reading, required this.active});

  final GaugeReading reading;

  /// Pulses radar rings while a scan is recording.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reading = this.reading;
    final (
      int? rssi,
      String title,
      String detail,
      String semantics,
    ) = switch (reading) {
      GaugeSignal(:final rssiDbm, :final bandLabel) => (
        rssiDbm,
        signalQualityFor(rssiDbm).label,
        [formatDbm(rssiDbm), ?bandLabel].join('  ·  '),
        'Signal: ${signalQualityFor(rssiDbm).label}, ${formatDbm(rssiDbm)}',
      ),
      GaugeMessage(:final title, :final detail) => (
        null,
        title,
        detail,
        '$title. $detail',
      ),
    };
    final animate = active && !MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: semantics,
      liveRegion: true,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: _RadarRings(animate: animate)),
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _fractionFor(rssi)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, fraction, _) => CustomPaint(
                  painter: _GaugePainter(
                    fraction: rssi == null ? null : fraction,
                    valueColor: rssi == null
                        ? scheme.outlineVariant
                        : AppColors.forQuality(signalQualityFor(rssi)),
                    trackColor: scheme.outlineVariant,
                    tickColor: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // The text keeps its wrap width and scales down as a block when
            // the gauge is small (sketch scan), so it never overflows.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  final pad = math.min(
                    _maxTextInsetPx,
                    box.maxWidth * _textInsetFraction,
                  );
                  return Padding(
                    padding: EdgeInsets.all(pad),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: box.maxWidth - 2 * pad,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              child: Text(
                                title,
                                style: textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              textAlign: TextAlign.center,
                              style: textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _fractionFor(int? rssi) {
    if (rssi == null) return 0;
    final clamped = rssi.clamp(gaugeMinDbm, gaugeMaxDbm);
    return (clamped - gaugeMinDbm) / (gaugeMaxDbm - gaugeMinDbm);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.valueColor,
    required this.trackColor,
    required this.tickColor,
  });

  /// 0..1 along the arc, or null for no reading.
  final double? fraction;
  final Color valueColor;
  final Color trackColor;
  final Color tickColor;

  static const double _stroke = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _stroke * 1.5;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    _drawBandTrack(canvas, arcRect);
    _drawTicks(canvas, center, radius);

    final f = fraction;
    if (f == null || f <= 0) return;
    final sweep = _sweepAngle * f;
    final glow = Paint()
      ..color = valueColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final arc = Paint()
      ..color = valueColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, _startAngle, sweep, false, glow);
    canvas.drawArc(arcRect, _startAngle, sweep, false, arc);

    final end = _startAngle + sweep;
    final knob = center + Offset(math.cos(end), math.sin(end)) * radius;
    canvas.drawCircle(knob, _stroke * 0.36, Paint()..color = Colors.white);
  }

  /// Faint band colours along the track, so the scale reads at a glance.
  void _drawBandTrack(Canvas canvas, Rect arcRect) {
    final base = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, _startAngle, _sweepAngle, false, base);

    final edges = [
      gaugeMinDbm,
      weakMinDbm,
      goodMinDbm,
      excellentMinDbm,
      gaugeMaxDbm,
    ];
    const bands = [
      SignalQuality.deadZone,
      SignalQuality.weak,
      SignalQuality.good,
      SignalQuality.excellent,
    ];
    for (var i = 0; i < bands.length; i++) {
      final from = (edges[i] - gaugeMinDbm) / (gaugeMaxDbm - gaugeMinDbm);
      final to = (edges[i + 1] - gaugeMinDbm) / (gaugeMaxDbm - gaugeMinDbm);
      final paint = Paint()
        ..color = AppColors.forQuality(bands[i]).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke;
      canvas.drawArc(
        arcRect,
        _startAngle + _sweepAngle * from,
        _sweepAngle * (to - from),
        false,
        paint,
      );
    }
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    const stepDbm = 10;
    final paint = Paint()
      ..color = tickColor.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final inner = radius - _stroke - 4;
    for (var dbm = gaugeMinDbm; dbm <= gaugeMaxDbm; dbm += stepDbm) {
      final t = (dbm - gaugeMinDbm) / (gaugeMaxDbm - gaugeMinDbm);
      final angle = _startAngle + _sweepAngle * t;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + dir * inner, center + dir * (inner - 8), paint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.valueColor != valueColor ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

/// Concentric rings behind the gauge; expand outward while recording.
class _RadarRings extends StatefulWidget {
  const _RadarRings({required this.animate});

  final bool animate;

  @override
  State<_RadarRings> createState() => _RadarRingsState();
}

class _RadarRingsState extends State<_RadarRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_RadarRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _RingsPainter(progress: _controller.value, color: color),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (var i = 0; i < _ringCount; i++) {
      final t = (progress + i / _ringCount) % 1.0;
      final radius = maxRadius * (0.35 + 0.65 * t);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.10 * (1 - t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.progress != progress || old.color != color;
}
