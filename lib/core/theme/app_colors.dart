import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Near-black blue stack for the app chrome and media surfaces.
  static const background = Color(0xFF03071D);
  static const surface = Color(0xFF071023);
  static const surfaceElevated = Color(0xFF0D1830);
  static const surfaceHighlight = Color(0xFF172542);

  /// Cyan accent matching the Play Store / launcher mark.
  static const primary = Color(0xFF00AEFF);
  static const primaryDark = Color(0xFF0088CC);
  static const accent = Color(0xFF5CD4FF);

  /// Foreground color used on top of the accent gradient (e.g. play pill icon).
  static const onAccent = Color(0xFF04121C);

  static const textPrimary = Color(0xFFEEF3FA);
  static const textSecondary = Color(0xFF94A3C4);
  static const textTertiary = Color(0xFF5C6B8A);

  static const divider = Color(0xFF18243E);
  static const error = Color(0xFFE5635A);
  static const success = Color(0xFF66CC8A);

  /// "Liked songs" heart color. Same hex as [error] today but kept separate so
  /// the two can diverge without coupling failure UI to favorites UI.
  static const like = Color(0xFFE5635A);
}
