import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_radius.dart';

Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    isScrollControlled: isScrollControlled,
    builder: (context) => GlassBottomSheet(
      showDragHandle: showDragHandle,
      child: Builder(builder: builder),
    ),
  );
}

class GlassBottomSheet extends StatelessWidget {
  const GlassBottomSheet({
    required this.child,
    this.showDragHandle = true,
    super.key,
  });

  final Widget child;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xxl),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.66),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, -1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 42,
                offset: const Offset(0, -14),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                if (showDragHandle)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.46),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const SizedBox(width: 36, height: 4),
                    ),
                  ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
