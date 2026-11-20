import 'package:flutter/material.dart';

import '../signal/signal_quality.dart';

/// Colour tokens (SPEC.md §11). Hex values are proposals.
abstract final class AppColors {
  static const Color accent = Color(0xFF3DD6F5);

  // Dark: true black with raised grey cards (watch-app style, 2026-11-21).
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceHigh = Color(0xFF2C2C2E);
  static const Color darkOutline = Color(0xFF3A3A3C);
  static const Color darkOnSurface = Color(0xFFF5F5F7);
  static const Color darkMuted = Color(0xFF98989F);

  // Light: soft grey page with white cards.
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFE5E5EA);
  static const Color lightOutline = Color(0xFFD1D1D6);
  static const Color lightOnSurface = Color(0xFF000000);
  static const Color lightMuted = Color(0xFF5F5F66);
  static const Color lightAccent = Color(0xFF00708A);

  static const Color excellent = Color(0xFF2EBD5A);
  static const Color good = Color(0xFFA6D33A);
  static const Color weak = Color(0xFFF2B233);
  static const Color deadZone = Color(0xFFE5484D);

  /// Heatmap colour for a signal band. Never use colour alone: pair it
  /// with [SignalQuality.label] and a pattern.
  static Color forQuality(SignalQuality quality) => switch (quality) {
        SignalQuality.excellent => excellent,
        SignalQuality.good => good,
        SignalQuality.weak => weak,
        SignalQuality.deadZone => deadZone,
      };
}
