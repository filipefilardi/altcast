import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/material.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart'
    as video_ctrl;
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/theme/app_colors.dart';

/// Material mobile controls: −10s / +30s, close + CC (tracks sheet) in the top
/// bar (visible in media_kit fullscreen), **brightness on the left** and
/// **volume on the right** via vertical drag only (no extra icon buttons).
MaterialVideoControlsThemeData buildAltCastMaterialVideoControlsTheme({
  required Player player,
  required Future<void> Function() onClosePlayer,
  required void Function(BuildContext origin) onOpenTracks,
  required void Function(BuildContext origin) onOpenSettings,
  required void Function(BuildContext origin) onOpenCast,
  required bool isCastActive,
  required void Function(BuildContext origin) onOpenSyncPlay,
  required bool isSyncPlayActive,
  required String title,
}) {
  final screenBrightness = ScreenBrightness();
  return MaterialVideoControlsThemeData(
    automaticallyImplySkipNextButton: false,
    automaticallyImplySkipPreviousButton: false,
    volumeGesture: true,
    brightnessGesture: true,
    seekGesture: true,
    gesturesEnabledWhileControlsVisible: true,
    // Keep captions anchored in a stable position; don't lift them when
    // controls fade in/out.
    shiftSubtitlesOnControlsVisibilityChange: false,
    seekOnDoubleTap: true,
    seekOnDoubleTapBackwardDuration: const Duration(seconds: 10),
    seekOnDoubleTapForwardDuration: const Duration(seconds: 30),
    initialVolume: (player.state.volume / 100.0).clamp(0.0, 1.0),
    onVolumeChanged: (v) => unawaited(player.setVolume(v * 100.0)),
    initialBrightness: 0.5,
    onBrightnessChanged: (v) =>
        unawaited(_applyScreenBrightness(screenBrightness, v)),
    onBrightnessReset: () =>
        unawaited(_resetScreenBrightness(screenBrightness)),
    seekBarPositionColor: AppColors.primary,
    seekBarThumbColor: AppColors.primary,
    buttonBarButtonColor: Colors.white,
    primaryButtonBar: const [
      Spacer(flex: 2),
      AltCastSeekRelativeButton(
        delta: Duration(seconds: -10),
        icon: Icons.replay_10_rounded,
      ),
      Spacer(),
      MaterialPlayOrPauseButton(iconSize: 56),
      Spacer(),
      AltCastSeekRelativeButton(
        delta: Duration(seconds: 30),
        icon: Icons.forward_30_rounded,
      ),
      Spacer(flex: 2),
    ],
    topButtonBar: [
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Close',
          onPressed: () => unawaited(onClosePlayer()),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: AltCastPlayerTitle(title: title)),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.cast_rounded,
          tooltip: 'Cast',
          color: isCastActive ? AppColors.primary : null,
          onPressed: () => onOpenCast(ctx),
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.groups_rounded,
          tooltip: 'SyncPlay',
          color: isSyncPlayActive ? AppColors.primary : null,
          onPressed: () => onOpenSyncPlay(ctx),
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.closed_caption_outlined,
          tooltip: 'Audio & subtitles',
          onPressed: () => onOpenTracks(ctx),
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Playback settings',
          onPressed: () => onOpenSettings(ctx),
        ),
      ),
    ],
    topButtonBarMargin: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
    bottomButtonBar: const [Expanded(child: AltCastSplitPositionIndicator())],
    bottomButtonBarMargin: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 42,
    ),
    seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 42),
  );
}

class AltCastSeekRelativeButton extends StatelessWidget {
  const AltCastSeekRelativeButton({
    super.key,
    required this.delta,
    required this.icon,
  });

  final Duration delta;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        final p = video_ctrl.controller(context).player;
        final pos = p.state.position;
        final dur = p.state.duration;
        if (dur <= Duration.zero) return;
        var next = pos + delta;
        if (next < Duration.zero) next = Duration.zero;
        if (next > dur) next = dur;
        await p.seek(next);
      },
      icon: Icon(icon),
      iconSize: 36,
      color: Colors.white,
      tooltip: delta.isNegative
          ? 'Back 10 seconds'
          : 'Forward ${delta.inSeconds} seconds',
    );
  }
}

class AltCastPlayerTitle extends StatelessWidget {
  const AltCastPlayerTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = title.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.95),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Position labels aligned to opposite sides of the controls row:
/// elapsed on the left, total on the right.
class AltCastSplitPositionIndicator extends StatelessWidget {
  const AltCastSplitPositionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final player = video_ctrl.controller(context).player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.state.duration;
        return Row(
          children: [
            Text(_formatPlayerTimestamp(position)),
            const Spacer(),
            Text(_formatPlayerTimestamp(duration)),
          ],
        );
      },
    );
  }
}

String _formatPlayerTimestamp(Duration value) {
  if (value.isNegative) value = Duration.zero;
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Prefer **system** backlight when allowed (real change on the panel).
/// On **Android** without `WRITE_SETTINGS`, skip system so we don’t spam the
/// permission screen — use **application** window brightness instead.
/// Application-only can be subtle during media_kit fullscreen; system is the
/// reliable path when `canChangeSystemBrightness` is true.
Future<void> _applyScreenBrightness(ScreenBrightness sb, double v) async {
  final x = v.clamp(0.0, 1.0);
  if (!kIsWeb) {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (await sb.canChangeSystemBrightness) {
          await sb.setSystemScreenBrightness(x);
          return;
        }
      } else {
        await sb.setSystemScreenBrightness(x);
        return;
      }
    } catch (e, st) {
      debugPrint('AltCast brightness (system): $e\n$st');
    }
  }
  try {
    await sb.setApplicationScreenBrightness(x);
  } catch (e, st) {
    debugPrint('AltCast brightness (application): $e\n$st');
  }
}

Future<void> _resetScreenBrightness(ScreenBrightness sb) async {
  try {
    await sb.resetApplicationScreenBrightness();
  } catch (e, st) {
    debugPrint('AltCast brightness reset (application): $e\n$st');
  }
}

/// Minimal player chrome action: icon-only, with a slightly larger tap target.
class AltCastChromeIconButton extends StatelessWidget {
  const AltCastChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: color ?? Colors.white.withValues(alpha: 0.95),
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
