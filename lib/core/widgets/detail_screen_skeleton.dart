import 'package:flutter/material.dart';

import 'package:altcast/core/widgets/detail_hero.dart';
import 'package:altcast/core/widgets/skeleton.dart';

/// Shared loading placeholder for media detail screens.
class DetailScreenSkeleton extends StatelessWidget {
  const DetailScreenSkeleton({
    super.key,
    this.actionWidth = 140,
    this.lineWidths = const [],
  });

  final double actionWidth;
  final List<double?> lineWidths;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Skeleton.group(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Skeleton.box(
                width: double.infinity,
                height: DetailHero.heightForWidth(
                  constraints.maxWidth,
                  MediaQuery.orientationOf(context),
                ),
                radius: 0,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Skeleton.group(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.box(width: actionWidth, height: 44),
                const SizedBox(height: 24),
                for (var i = 0; i < lineWidths.length; i++) ...[
                  if (lineWidths[i] == null)
                    Skeleton.line()
                  else
                    Skeleton.line(width: lineWidths[i]!),
                  if (i < lineWidths.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
