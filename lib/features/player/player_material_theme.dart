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
}) {
  final screenBrightness = ScreenBrightness();
  return MaterialVideoControlsThemeData(
    automaticallyImplySkipNextButton: false,
    automaticallyImplySkipPreviousButton: false,
    volumeGesture: true,
    brightnessGesture: true,
    seekGesture: true,
    gesturesEnabledWhileControlsVisible: true,
    shiftSubtitlesOnControlsVisibilityChange: true,
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
          icon: Icons.close_rounded,
          tooltip: 'Close',
          onPressed: () => unawaited(onClosePlayer()),
        ),
      ),
      const Spacer(),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.closed_caption_outlined,
          tooltip: 'Audio & subtitles',
          onPressed: () => onOpenTracks(ctx),
        ),
      ),
    ],
    topButtonBarMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    bottomButtonBar: const [MaterialPositionIndicator(), Spacer()],
    bottomButtonBarMargin: const EdgeInsets.only(
      left: 16,
      right: 8,
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

/// Round translucent control matching the player’s corner affordances.
class AltCastChromeIconButton extends StatelessWidget {
  const AltCastChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.48),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white.withValues(alpha: 0.95)),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
