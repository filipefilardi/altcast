import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppGradients {
  AppGradients._();

  /// Cyan ramp (bright → darker), used on the primary play button and login CTA.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );

  /// Slim version for thin progress bars.
  static const accentHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );

  /// Soft cyan radial used on the login backdrop.
  static const loginBackdrop = RadialGradient(
    center: Alignment(0, -0.6),
    radius: 1.1,
    colors: [Color(0x3300AEFF), AppColors.background],
    stops: [0.0, 0.85],
  );
}
