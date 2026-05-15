import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Animated shimmer building blocks for loading states.
///
/// Wrap the layout you want to fake in [Skeleton.group] (which provides the
/// shimmer animation), then place [Skeleton.box] / [Skeleton.line] /
/// [Skeleton.circle] inside.
class Skeleton {
  Skeleton._();

  static Widget group({required Widget child}) => _SkeletonGroup(child: child);

  static Widget box({
    required double width,
    required double height,
    double radius = 12,
  }) => _SkeletonBox(width: width, height: height, radius: radius);

  static Widget line({double width = double.infinity, double height = 12}) =>
      _SkeletonBox(width: width, height: height, radius: height / 2);

  static Widget circle({required double size}) =>
      _SkeletonBox(width: size, height: size, radius: size);
}

class _SkeletonGroup extends StatefulWidget {
  const _SkeletonGroup({required this.child});
  final Widget child;

  @override
  State<_SkeletonGroup> createState() => _SkeletonGroupState();
}

class _SkeletonGroupState extends State<_SkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return _ShimmerScope(progress: _ctrl.value, child: child!);
      },
      child: widget.child,
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.progress, required super.child});
  final double progress;

  @override
  bool updateShouldNotify(covariant _ShimmerScope oldWidget) =>
      oldWidget.progress != progress;
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();
    final t = scope?.progress ?? 0;
    final start = t * 2 - 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(start - 0.6, 0),
              end: Alignment(start + 0.6, 0),
              colors: const [
                AppColors.surfaceElevated,
                AppColors.surfaceHighlight,
                AppColors.surfaceElevated,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcIn,
          child: Container(color: AppColors.surfaceElevated),
        ),
      ),
    );
  }
}
