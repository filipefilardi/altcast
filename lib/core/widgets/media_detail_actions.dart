import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/detail_action_row.dart';
import 'package:altcast/core/widgets/play_button.dart';
import 'package:altcast/core/widgets/user_data_actions.dart';

/// Shared action strip for detail screens (movie/series), with the primary
/// Play/Resume CTA and common secondary controls.
class MediaDetailActions extends StatelessWidget {
  const MediaDetailActions({
    super.key,
    required this.onPlay,
    required this.playLabel,
    required this.initialPlayed,
    required this.onSetPlayed,
    required this.initialFavorite,
    required this.onSetFavorite,
    required this.downloadAction,
    this.playIcon = PiconsFill.play,
    this.onPlayFromStart,
    this.onCast,
    this.castActive = false,
  });

  final VoidCallback? onPlay;
  final String playLabel;
  final IconData playIcon;
  final VoidCallback? onPlayFromStart;
  final bool initialPlayed;
  final Future<void> Function(bool) onSetPlayed;
  final bool initialFavorite;
  final Future<void> Function(bool) onSetFavorite;
  final VoidCallback? onCast;
  final bool castActive;
  final Widget downloadAction;

  @override
  Widget build(BuildContext context) {
    return DetailActionRow(
      primary: PlayButton(onPressed: onPlay, label: playLabel, icon: playIcon),
      actions: [
        if (onPlayFromStart != null)
          IconButton(
            iconSize: 22,
            icon: const Icon(PiconsRegular.arrowCounterClockwise),
            tooltip: 'Play from start',
            onPressed: onPlayFromStart,
          ),
        UserDataActions(
          initialPlayed: initialPlayed,
          onSetPlayed: onSetPlayed,
          initialFavorite: initialFavorite,
          onSetFavorite: onSetFavorite,
        ),
        if (onCast != null)
          IconButton(
            iconSize: 22,
            icon: Icon(
              PiconsRegular.screencast,
              color: castActive ? AppColors.primary : null,
            ),
            tooltip: 'Play on…',
            onPressed: onCast,
          ),
        downloadAction,
      ],
    );
  }
}
