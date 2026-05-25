import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_radius.dart';
import 'package:altcast/core/theme/app_spacing.dart';

/// Opens a floating glass popover anchored to the widget that owns [context].
Future<T?> showGlassPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double width = 280,
  double maxHeight = 420,
  Rect? anchorRect,
}) {
  final anchor = anchorRect ?? _anchorRectFor(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GlassPopoverRoute<T>(
      anchor: anchor,
      width: width,
      maxHeight: maxHeight,
      builder: builder,
    ),
  );
}

Rect? _anchorRectFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
}

class _GlassPopoverRoute<T> extends PopupRoute<T> {
  _GlassPopoverRoute({
    required this.anchor,
    required this.width,
    required this.maxHeight,
    required this.builder,
  });

  final Rect? anchor;
  final double width;
  final double maxHeight;
  final WidgetBuilder builder;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.15);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: CustomSingleChildLayout(
        delegate: _PopoverLayoutDelegate(
          anchor: anchor,
          preferredWidth: width,
          maxHeight: maxHeight,
          screenSize: mq.size,
        ),
        child: _GlassPanel(
          maxHeight: maxHeight,
          child: Builder(builder: builder),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: _scaleAlignment(context),
        child: child,
      ),
    );
  }

  Alignment _scaleAlignment(BuildContext context) {
    final a = anchor;
    if (a == null) return Alignment.center;
    final screenSize = MediaQuery.of(context).size;
    final dx = (a.center.dx / screenSize.width) * 2 - 1;
    final dy = a.center.dy < screenSize.height / 2 ? -1.0 : 1.0;
    return Alignment(dx.clamp(-1.0, 1.0), dy);
  }
}

class _PopoverLayoutDelegate extends SingleChildLayoutDelegate {
  _PopoverLayoutDelegate({
    required this.anchor,
    required this.preferredWidth,
    required this.maxHeight,
    required this.screenSize,
  });

  final Rect? anchor;
  final double preferredWidth;
  final double maxHeight;
  final Size screenSize;

  static const double _edge = AppSpacing.sm;
  static const double _gap = AppSpacing.xs;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = preferredWidth.clamp(0.0, constraints.maxWidth - _edge * 2);
    return BoxConstraints(
      minWidth: 0,
      maxWidth: width,
      minHeight: 0,
      maxHeight: maxHeight.clamp(0.0, constraints.maxHeight - _edge * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final a = anchor;
    if (a == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    double x = a.right - childSize.width;
    if (x < _edge) x = _edge;
    if (x + childSize.width > size.width - _edge) {
      x = size.width - _edge - childSize.width;
    }

    final spaceBelow = size.height - a.bottom - _gap - _edge;
    double y;
    if (spaceBelow >= childSize.height) {
      y = a.bottom + _gap;
    } else {
      y = a.top - _gap - childSize.height;
      if (y < _edge) y = _edge;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _PopoverLayoutDelegate old) {
    return old.anchor != anchor ||
        old.preferredWidth != preferredWidth ||
        old.maxHeight != maxHeight ||
        old.screenSize != screenSize;
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, required this.maxHeight});

  final Widget child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassPopoverItem extends StatelessWidget {
  const GlassPopoverItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.error
        : (enabled ? AppColors.textPrimary : AppColors.textTertiary);
    return InkWell(
      onTap: enabled
          ? () {
              Navigator.of(context).pop();
              onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
