import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/material.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart'
    as video_ctrl;
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/theme/app_colors.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';
import '../remote/remote_providers.dart';
import '../syncplay/syncplay_controller.dart';

/// Material mobile controls: −10s / +30s, close + CC (tracks sheet) in the top
/// bar (visible in media_kit fullscreen), **brightness on the left** and
/// **volume on the right** via vertical drag only (no extra icon buttons).
MaterialVideoControlsThemeData buildAltCastMaterialVideoControlsTheme({
  required Player player,
  required Future<void> Function() onClosePlayer,
  required void Function(BuildContext origin) onOpenTracks,
  required void Function(BuildContext origin) onOpenSettings,
  required void Function(BuildContext origin) onOpenCast,
  required void Function(BuildContext origin) onOpenSyncPlay,
  required VoidCallback onRotateOrientation,
  required void Function(double value) onVolumeChanged,
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
    onVolumeChanged: onVolumeChanged,
    initialBrightness: 0.5,
    onBrightnessChanged: (v) =>
        unawaited(_applyScreenBrightness(screenBrightness, v)),
    onBrightnessReset: () =>
        unawaited(_resetScreenBrightness(screenBrightness)),
    volumeIndicatorBuilder: (context, value) => Consumer(
      builder: (_, ref, _) {
        final castActive = ref.watch(activeRemoteSessionIdProvider) != null;
        return _VerticalGestureIndicator(
          alignment: Alignment.centerRight,
          value: value,
          icon: value == 0.0
              ? Icons.volume_off_rounded
              : value < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          activeColor: castActive ? AppColors.primary : Colors.white,
        );
      },
    ),
    brightnessIndicatorBuilder: (_, value) => _VerticalGestureIndicator(
      alignment: Alignment.centerLeft,
      value: value,
      icon: value < 1.0 / 3.0
          ? Icons.brightness_low_rounded
          : value < 2.0 / 3.0
          ? Icons.brightness_medium_rounded
          : Icons.brightness_high_rounded,
      activeColor: Colors.white,
    ),
    seekBarPositionColor: AppColors.primary,
    seekBarThumbColor: AppColors.primary,
    seekBarHeight: 5.0,
    seekBarThumbSize: 14.0,
    buttonBarButtonColor: Colors.white,
    primaryButtonBar: const [
      Spacer(flex: 2),
      AltCastSeekRelativeButton(
        delta: Duration(seconds: -10),
        icon: Icons.replay_10_rounded,
      ),
      Spacer(),
      AltCastPlayPauseButton(iconSize: 56),
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
        builder: (ctx) => Consumer(
          builder: (_, ref, _) {
            final active = ref.watch(syncPlayControllerProvider).isActive;
            return AltCastChromeIconButton(
              icon: Icons.groups_rounded,
              tooltip: 'SyncPlay',
              color: active ? AppColors.primary : null,
              onPressed: () => onOpenSyncPlay(ctx),
            );
          },
        ),
      ),
      Builder(
        builder: (ctx) => Consumer(
          builder: (_, ref, _) {
            final active = ref.watch(activeRemoteSessionIdProvider) != null;
            return AltCastChromeIconButton(
              icon: Icons.cast_rounded,
              tooltip: 'Cast',
              color: active ? AppColors.primary : null,
              onPressed: () => onOpenCast(ctx),
            );
          },
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: Icons.screen_rotation_rounded,
          tooltip: 'Rotate',
          onPressed: onRotateOrientation,
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

class AltCastSeekRelativeButton extends ConsumerWidget {
  const AltCastSeekRelativeButton({
    super.key,
    required this.delta,
    required this.icon,
  });

  final Duration delta;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () async {
        final p = video_ctrl.controller(context).player;
        final remote = ref.read(activeRemoteSessionProvider).value;
        final remotePosition = remote?.estimatedPosition();
        final remoteDurationTicks = remote?.runTimeTicks;
        final pos = remotePosition ?? p.state.position;
        final dur = remoteDurationTicks != null && remoteDurationTicks > 0
            ? Duration(microseconds: remoteDurationTicks ~/ 10)
            : p.state.duration;
        if (dur <= Duration.zero) return;
        var next = pos + delta;
        if (next < Duration.zero) next = Duration.zero;
        if (next > dur) next = dur;
        if (remote != null && remote.isPlayingSomething) {
          await ref
              .read(remoteSessionsRepositoryProvider)
              .seek(remote.id, next);
          await p.seek(next);
        } else {
          await p.seek(next);
        }
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

class _VerticalGestureIndicator extends StatelessWidget {
  const _VerticalGestureIndicator({
    required this.alignment,
    required this.value,
    required this.icon,
    required this.activeColor,
  });

  final Alignment alignment;
  final double value;
  final IconData icon;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: SizedBox(
          width: 54,
          height: 164,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                children: [
                  Icon(icon, color: activeColor, size: 22),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        return Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              width: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Container(
                              width: 4,
                              height: constraints.maxHeight * clamped,
                              decoration: BoxDecoration(
                                color: activeColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Positioned(
                              bottom: (constraints.maxHeight - 10) * clamped,
                              child: SizedBox.square(
                                dimension: 12,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: activeColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.34,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(clamped * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AltCastPlayPauseButton extends ConsumerWidget {
  const AltCastPlayPauseButton({super.key, this.iconSize});

  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(activeRemoteSessionProvider).value;
    if (remote != null && remote.isPlayingSomething) {
      return IconButton(
        icon: Icon(
          remote.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        ),
        iconSize: iconSize ?? 48,
        color: Colors.white,
        tooltip: remote.isPaused ? 'Play' : 'Pause',
        onPressed: () =>
            ref.read(remoteSessionsRepositoryProvider).playPause(remote.id),
      );
    }

    final player = video_ctrl.controller(context).player;
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (_, snapshot) {
        final playing = snapshot.data ?? false;
        return IconButton(
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          iconSize: iconSize ?? 48,
          color: Colors.white,
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: () async {
            if (player.state.playing) {
              await player.pause();
            } else {
              await player.play();
            }
          },
        );
      },
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
