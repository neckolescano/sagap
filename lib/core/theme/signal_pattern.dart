import 'package:flutter/material.dart';

import '../signal/signal_quality.dart';
import 'app_colors.dart';

/// Fills a rect with the band colour plus a band-specific pattern, so the
/// legend and heatmap never rely on colour alone (SPEC.md §3, §11):
/// Excellent solid · Good dots · Weak diagonal lines · Dead zone cross-hatch.
class SignalPatternPainter extends CustomPainter {
  const SignalPatternPainter(this.quality, {required this.inkColor, this.opacity = 1});

  final SignalQuality quality;

  /// Colour of the pattern marks drawn over the band colour.
  final Color inkColor;

  /// Overall opacity; the heatmap fades predicted cells (SPEC.md §8).
  final double opacity;

  static const double _spacing = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = AppColors.forQuality(quality);
    canvas.drawRect(rect, Paint()..color = fill.withValues(alpha: fill.a * opacity));
    final ink = Paint()
      ..color = inkColor.withValues(alpha: inkColor.a * opacity)
      ..strokeWidth = 1.4;
    canvas.save();
    canvas.clipRect(rect);
    switch (quality) {
      case SignalQuality.excellent:
        break;
      case SignalQuality.good:
        for (var y = _spacing / 2; y < size.height; y += _spacing) {
          for (var x = _spacing / 2; x < size.width; x += _spacing) {
            canvas.drawCircle(Offset(x, y), 1.2, ink);
          }
        }
      case SignalQuality.weak:
        _diagonals(canvas, size, ink, forward: true);
      case SignalQuality.deadZone:
        _diagonals(canvas, size, ink, forward: true);
        _diagonals(canvas, size, ink, forward: false);
    }
    canvas.restore();
  }

  void _diagonals(Canvas canvas, Size size, Paint ink, {required bool forward}) {
    final span = size.width + size.height;
    for (var d = -size.height; d < span; d += _spacing) {
      if (forward) {
        canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), ink);
      } else {
        canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), ink);
      }
    }
  }

  @override
  bool shouldRepaint(SignalPatternPainter old) =>
      old.quality != quality || old.inkColor != inkColor || old.opacity != opacity;
}

/// Pattern ink that reads on all four band colours.
const Color patternInk = Color(0x8C0A0F1C);

/// Small rounded swatch for a band.
class SignalSwatch extends StatelessWidget {
  const SignalSwatch(this.quality, {super.key, this.size = 20});

  final SignalQuality quality;
  final double size;

  /// Dark ink reads on all four band colours.
  static const Color _ink = patternInk;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: CustomPaint(
        size: Size.square(size),
        painter: SignalPatternPainter(quality, inkColor: _ink),
      ),
    );
  }
}
