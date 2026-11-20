import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Minimum height for primary actions (one-handed use, SPEC.md §11).
const double primaryActionHeight = 64;

/// Corner radius for cards and sheets.
const double cardRadius = 20;

/// Material 3 themes built from [AppColors]. Dark is the default.
abstract final class AppTheme {
  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.darkBackground,
          surface: AppColors.darkBackground,
          surfaceContainer: AppColors.darkSurface,
          surfaceContainerHigh: AppColors.darkSurfaceHigh,
          onSurface: AppColors.darkOnSurface,
          onSurfaceVariant: AppColors.darkMuted,
          outlineVariant: AppColors.darkOutline,
        ),
      );

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.lightAccent,
          onPrimary: AppColors.lightSurface,
          surface: AppColors.lightBackground,
          surfaceContainer: AppColors.lightSurface,
          surfaceContainerHigh: AppColors.lightSurfaceHigh,
          onSurface: AppColors.lightOnSurface,
          onSurfaceVariant: AppColors.lightMuted,
          outlineVariant: AppColors.lightOutline,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    const actionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
    );
    const actionSize = Size(64, primaryActionHeight);
    const actionText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(cardRadius)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: actionSize,
          shape: actionShape,
          textStyle: actionText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: actionSize,
          shape: actionShape,
          textStyle: actionText,
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        showDragHandle: true,
      ),
    );
  }
}
