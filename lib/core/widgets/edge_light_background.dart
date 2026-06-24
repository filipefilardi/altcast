import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';

class EdgeLightBackground extends StatelessWidget {
  const EdgeLightBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 700;
    final glowDiameter =
        (isWide
                ? (size.width * 0.52).clamp(
                    size.height * 0.72,
                    size.height * 0.92,
                  )
                : size.width * 1.28)
            .clamp(360.0, 1280.0);

    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgeLightPainter(glowDiameter: glowDiameter),
            ),
          ),
          Positioned.fill(
            child: Theme(
              data: theme.copyWith(
                scaffoldBackgroundColor: Colors.transparent,
                appBarTheme: theme.appBarTheme.copyWith(
                  backgroundColor: Colors.transparent,
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeLightPainter extends CustomPainter {
  const _EdgeLightPainter({required this.glowDiameter});

  final double glowDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundRect = Offset.zero & size;
    final diagonalPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          AppColors.primary.withValues(alpha: 0.16),
          AppColors.primaryDark.withValues(alpha: 0.07),
          Colors.transparent,
          Colors.transparent,
          AppColors.primaryDark.withValues(alpha: 0.06),
          AppColors.accent.withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.22, 0.42, 0.6, 0.8, 1.0],
      ).createShader(backgroundRect);
    final center = Offset(
      size.width + glowDiameter * 0.08,
      -glowDiameter * 0.18,
    );
    final accentPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowDiameter * 0.2);
    final highlightPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowDiameter * 0.12);

    canvas.drawRect(backgroundRect, diagonalPaint);

    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: glowDiameter * 1.18,
        height: glowDiameter * 0.86,
      ),
      accentPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - glowDiameter * 0.08, center.dy + 12),
        width: glowDiameter * 0.72,
        height: glowDiameter * 0.44,
      ),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EdgeLightPainter oldDelegate) {
    return oldDelegate.glowDiameter != glowDiameter;
  }
}
