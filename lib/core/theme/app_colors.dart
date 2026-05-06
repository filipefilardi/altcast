import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Dark charcoal stack aligned with AltSound.
  static const background = Color(0xFF0B0E12);
  static const surface = Color(0xFF151922);
  static const surfaceElevated = Color(0xFF1B212B);
  static const surfaceHighlight = Color(0xFF242B36);

  /// Cyan accent matching the Play Store / launcher mark.
  static const primary = Color(0xFF00AEFF);
  static const primaryDark = Color(0xFF0088CC);
  static const accent = Color(0xFF5CD4FF);

  /// Foreground color used on top of the accent gradient (e.g. play pill icon).
  static const onAccent = Color(0xFF04121C);

  static const textPrimary = Color(0xFFF7F8F5);
  static const textSecondary = Color(0xFFA6B4B8);
  static const textTertiary = Color(0xFF617279);

  static const divider = Color(0xFF2D3540);
  static const error = Color(0xFFE5635A);
  static const success = Color(0xFF66CC8A);

  /// "Liked songs" heart color. Same hex as [error] today but kept separate so
  /// the two can diverge without coupling failure UI to favorites UI.
  static const like = Color(0xFFE5635A);
}
