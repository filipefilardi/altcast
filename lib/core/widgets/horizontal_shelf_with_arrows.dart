import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';

class HorizontalShelfWithArrows extends StatefulWidget {
  const HorizontalShelfWithArrows({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
    this.scrollStepFraction = 0.82,
    this.buttonInset = 8,
  });

  final ScrollController controller;
  final Widget child;
  final bool enabled;
  final double scrollStepFraction;
  final double buttonInset;

  @override
  State<HorizontalShelfWithArrows> createState() =>
      _HorizontalShelfWithArrowsState();
}

class _HorizontalShelfWithArrowsState extends State<HorizontalShelfWithArrows> {
  bool _canScrollBackward = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshScrollActions);
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant HorizontalShelfWithArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refreshScrollActions);
    widget.controller.addListener(_refreshScrollActions);
    _scheduleRefresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshScrollActions);
    super.dispose();
  }

  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshScrollActions();
    });
  }

  void _refreshScrollActions() {
    if (!mounted) return;
    final c = widget.controller;
    final hasClients = c.hasClients;
    final maxExtent = hasClients ? c.position.maxScrollExtent : 0.0;
    final canBackward = hasClients && c.offset > 1.0;
    final canForward = hasClients && c.offset < maxExtent - 1.0;

    if (_canScrollBackward == canBackward && _canScrollForward == canForward) {
      return;
    }
    setState(() {
      _canScrollBackward = canBackward;
      _canScrollForward = canForward;
    });
  }

  Future<void> _scrollByViewportFactor(double direction) async {
    final c = widget.controller;
    if (!c.hasClients) return;

    final position = c.position;
    final delta = position.viewportDimension * widget.scrollStepFraction;
    final target = (c.offset + (delta * direction)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((target - c.offset).abs() < 0.5) return;
    await c.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: widget.buttonInset,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_canScrollBackward,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _canScrollBackward ? 1 : 0,
              child: Center(
                child: _ShelfArrowButton(
                  icon: PiconsRegular.caretLeft,
                  tooltip: 'Scroll left',
                  onPressed: () => _scrollByViewportFactor(-1),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: widget.buttonInset,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_canScrollForward,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _canScrollForward ? 1 : 0,
              child: Center(
                child: _ShelfArrowButton(
                  icon: PiconsRegular.caretRight,
                  tooltip: 'Scroll right',
                  onPressed: () => _scrollByViewportFactor(1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfArrowButton extends StatelessWidget {
  const _ShelfArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: AppColors.textPrimary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.92),
        minimumSize: const Size(38, 38),
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
