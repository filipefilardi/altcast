import 'package:flutter/material.dart';

/// Shared detail-page action layout: primary play/resume control on the left,
/// secondary icon actions grouped on the right and allowed to wrap on narrow
/// screens.
class DetailActionRow extends StatelessWidget {
  const DetailActionRow({
    super.key,
    required this.primary,
    this.actions = const [],
  });

  final Widget primary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return primary;
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          primary,
          const Spacer(),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );
  }
}
