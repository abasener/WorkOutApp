import 'package:flutter/material.dart';

abstract class AppColors {
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF161616);
  static const Color surfaceRaised = Color(0xFF1F1F1F);
  static const Color border = Color(0xFF2C2C2C);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF9A9A9A);
  static const Color textFaint = Color(0xFF5C5C5C);

  static const Color accent = Color(0xFFE0263D); // red
  static const Color accentDim = Color(0xFF5C1620);
  static const Color good = Color(0xFF3FA75C);
  static const Color warn = Color(0xFFE0A62D);

  /// Softer, less saturated red used for muscle-map highlights (soreness map,
  /// "muscles worked" diagram) — the full-bright `accent` red read as too
  /// intense/harsh when filling large body-silhouette regions rather than
  /// small UI accents.
  static const Color muscleHigh = Color(0xFFA13A3A);
}

abstract class AppSpacing {
  static const double micro = 4;
  static const double small = 8;
  static const double standard = 12;
  static const double cardPad = 16;
  static const double edge = 20;
  static const double large = 24;
  static const double xLarge = 32;
  static const double cardGap = 12;
}

abstract class AppRadius {
  static const double pill = 100;
  static const double button = 12;
  static const double card = 16;
}

abstract class AppText {
  static const pageHeader = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const subHeader = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const bodyText = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary);
  static const smallText = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
  static const label = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
  static const bigNumber = TextStyle(
      fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.textPrimary);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.accent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: AppColors.surface,
      elevation: 0,
    ),
    dividerColor: AppColors.border,
    fontFamily: 'Roboto',
  );
}
