import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF0E0B14);
  static const surface = Color(0xFF16121E);
  static const surfaceElevated = Color(0xFF1E1A28);
  static const surfaceHighlight = Color(0xFF2A2438);

  static const primary = Color(0xFF7B68EE);
  static const primaryDark = Color(0xFF5A4EC8);
  static const accent = Color(0xFFA78BFA);

  /// Foreground color used on top of the accent gradient (e.g. play pill icon).
  static const onAccent = Color(0xFF1A0F05);

  static const textPrimary = Color(0xFFF5F1EA);
  static const textSecondary = Color(0xFFA39EB0);
  static const textTertiary = Color(0xFF6A6378);

  static const divider = Color(0xFF2A2438);
  static const error = Color(0xFFE5635A);

  /// "Liked songs" heart color. Same hex as [error] today but kept separate so
  /// the two can diverge without coupling failure UI to favorites UI.
  static const like = Color(0xFFE5635A);
}
