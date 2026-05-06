import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ExpandableText extends StatefulWidget {
  const ExpandableText({
    required this.text,
    super.key,
    this.style,
    this.collapsedMaxLines = 4,
    this.expandLabel = 'Show more',
    this.collapseLabel = 'Show less',
  });

  final String text;
  final TextStyle? style;
  final int collapsedMaxLines;
  final String expandLabel;
  final String collapseLabel;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final effectiveStyle =
        textTheme.bodyMedium?.merge(widget.style) ?? widget.style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          maxLines: widget.collapsedMaxLines,
        )..layout(maxWidth: constraints.maxWidth);

        final hasOverflow = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: effectiveStyle,
              maxLines: _expanded ? null : widget.collapsedMaxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (hasOverflow)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      _expanded ? widget.collapseLabel : widget.expandLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
