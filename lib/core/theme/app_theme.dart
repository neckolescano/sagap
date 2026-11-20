import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Minimum height for primary actions (one-handed use, SPEC.md §11).
const double primaryActionHeight = 64;

/// Corner radius for cards and sheets.
const double cardRadius = 26;

/// Bottom padding for a tab's scrolling content: the floating tab bar's
/// height (Scaffold.extendBody puts it in the MediaQuery padding) plus a gap.
double tabContentBottomPadding(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;

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
    // Pill-shaped actions and borderless rounded cards (watch-app style).
    const actionShape = StadiumBorder();
    const actionSize = Size(64, primaryActionHeight);
    const actionText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    final textTheme = base.textTheme.copyWith(
      // Large collapsing page titles (SliverAppBar.large) use this.
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
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
