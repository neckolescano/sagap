import 'package:flutter/material.dart';

import '../signal/signal_quality.dart';

/// Colour tokens (SPEC.md §11). Hex values are proposals.
abstract final class AppColors {
  static const Color accent = Color(0xFF3DD6F5);

  static const Color darkBackground = Color(0xFF0A0F1C);
  static const Color darkSurface = Color(0xFF121A2B);
  static const Color darkSurfaceHigh = Color(0xFF1A2438);
  static const Color darkOutline = Color(0xFF2A3650);
  static const Color darkOnSurface = Color(0xFFE6ECF5);
  static const Color darkMuted = Color(0xFF8B97AD);

  static const Color lightBackground = Color(0xFFF4F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFE8EEF6);
  static const Color lightOutline = Color(0xFFD3DCE8);
  static const Color lightOnSurface = Color(0xFF0A0F1C);
  static const Color lightMuted = Color(0xFF5A6780);
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
