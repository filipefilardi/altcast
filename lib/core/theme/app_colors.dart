import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Navy stack aligned with adaptive icon background `#18265D` + foreground.
  static const background = Color(0xFF0A0F24);
  static const surface = Color(0xFF121A35);
  static const surfaceElevated = Color(0xFF1A2448);
  static const surfaceHighlight = Color(0xFF283364);

  /// Cyan accent matching the Play Store / launcher mark.
  static const primary = Color(0xFF00AEFF);
  static const primaryDark = Color(0xFF0088CC);
  static const accent = Color(0xFF5CD4FF);

  /// Foreground color used on top of the accent gradient (e.g. play pill icon).
  static const onAccent = Color(0xFF04121C);

  static const textPrimary = Color(0xFFEEF3FA);
  static const textSecondary = Color(0xFF94A3C4);
  static const textTertiary = Color(0xFF5C6B8A);

  static const divider = Color(0xFF243058);
  static const error = Color(0xFFE5635A);
  static const success = Color(0xFF66CC8A);

  /// "Liked songs" heart color. Same hex as [error] today but kept separate so
  /// the two can diverge without coupling failure UI to favorites UI.
  static const like = Color(0xFFE5635A);
}
