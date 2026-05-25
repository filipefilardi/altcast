import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/material.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart'
    as video_ctrl;
import 'package:screen_brightness/screen_brightness.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/jellyfin/remote_sessions_repository.dart';
import 'package:altcast/data/jellyfin/models/stream_source.dart';
import 'package:altcast/features/remote/remote_providers.dart';
import 'package:altcast/features/syncplay/syncplay_controller.dart';

const bool _trickplayDebugLogs = true;

class TrickplayOverlayData {
  const TrickplayOverlayData({
    required this.session,
    required this.position,
    required this.totalDuration,
    required this.alignPercent,
  });

  final TrickplaySession session;
  final Duration position;
  final Duration totalDuration;
  final double alignPercent;
}

/// Material mobile controls: −10s / +30s, close + CC (tracks sheet) in the top
/// bar (visible in media_kit fullscreen), **brightness on the left** and
/// **volume on the right** via vertical drag only (no extra icon buttons).
MaterialVideoControlsThemeData buildAltCastMaterialVideoControlsTheme({
  required Player player,
  required String itemId,
  required ValueListenable<StreamSource?> sourceListenable,
  required ValueNotifier<TrickplayOverlayData?> trickplayOverlayNotifier,
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
    displaySeekBar: false,
    visibleOnMount: true,
    controlsHoverDuration: const Duration(seconds: 20),
    automaticallyImplySkipNextButton: false,
    automaticallyImplySkipPreviousButton: false,
    volumeGesture: true,
    brightnessGesture: true,
    seekGesture: false,
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
              ? PiconsRegular.speakerSlash
              : value < 0.5
              ? PiconsRegular.speakerHigh
              : PiconsRegular.speakerHigh,
          activeColor: castActive ? AppColors.primary : Colors.white,
        );
      },
    ),
    brightnessIndicatorBuilder: (_, value) => _VerticalGestureIndicator(
      alignment: Alignment.centerLeft,
      value: value,
      icon: value < 1.0 / 3.0
          ? PiconsRegular.sunDim
          : value < 2.0 / 3.0
          ? PiconsRegular.sun
          : PiconsRegular.sunHorizon,
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
        icon: PiconsRegular.rewind,
      ),
      Spacer(),
      AltCastPlayPauseButton(iconSize: 56),
      Spacer(),
      AltCastSeekRelativeButton(
        delta: Duration(seconds: 30),
        icon: PiconsRegular.fastForward,
      ),
      Spacer(flex: 2),
    ],
    topButtonBar: [
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: PiconsRegular.caretLeft,
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
              icon: PiconsRegular.usersThree,
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
              icon: PiconsRegular.screencast,
              tooltip: 'Cast',
              color: active ? AppColors.primary : null,
              onPressed: () => onOpenCast(ctx),
            );
          },
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: PiconsRegular.deviceRotate,
          tooltip: 'Rotate',
          onPressed: onRotateOrientation,
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: PiconsRegular.closedCaptioning,
          tooltip: 'Audio & subtitles',
          onPressed: () => onOpenTracks(ctx),
        ),
      ),
      Builder(
        builder: (ctx) => AltCastChromeIconButton(
          icon: PiconsRegular.gear,
          tooltip: 'Playback settings',
          onPressed: () => onOpenSettings(ctx),
        ),
      ),
    ],
    topButtonBarMargin: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
    bottomButtonBar: [
      Expanded(
        child: AltCastTrickplaySeekGroup(
          itemId: itemId,
          sourceListenable: sourceListenable,
          trickplayOverlayNotifier: trickplayOverlayNotifier,
        ),
      ),
    ],
    bottomButtonBarMargin: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 4,
    ),
    buttonBarHeight: 96,
    seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
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
        icon: Icon(remote.isPaused ? PiconsFill.play : PiconsFill.pause),
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
          icon: Icon(playing ? PiconsFill.pause : PiconsFill.play),
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

class AltCastTrickplaySeekGroup extends ConsumerStatefulWidget {
  const AltCastTrickplaySeekGroup({
    super.key,
    required this.itemId,
    required this.sourceListenable,
    required this.trickplayOverlayNotifier,
  });

  final String itemId;
  final ValueListenable<StreamSource?> sourceListenable;
  final ValueNotifier<TrickplayOverlayData?> trickplayOverlayNotifier;

  @override
  ConsumerState<AltCastTrickplaySeekGroup> createState() =>
      _AltCastTrickplaySeekGroupState();
}

class _AltCastTrickplaySeekGroupState
    extends ConsumerState<AltCastTrickplaySeekGroup> {
  TrickplaySession? _trickplay;
  Object? _lastManifestKey;
  bool _isScrubbing = false;
  double _scrubPercent = 0.0;
  double? _hoverPercent;

  @override
  void initState() {
    super.initState();
    widget.sourceListenable.addListener(_loadTrickplay);
    unawaited(_loadTrickplay());
  }

  @override
  void dispose() {
    widget.trickplayOverlayNotifier.value = null;
    widget.sourceListenable.removeListener(_loadTrickplay);
    super.dispose();
  }

  Future<void> _loadTrickplay() async {
    final source = widget.sourceListenable.value;
    final key = '${widget.itemId}::${source?.mediaSourceId ?? ''}';
    if (key == _lastManifestKey) return;
    _lastManifestKey = key;
    try {
      TrickplaySession? session;
      final localUrl = source?.url ?? '';
      final isLocal = localUrl.startsWith('file://');
      if (isLocal) {
        final localItem = ref
            .read(downloadManagerProvider)
            .items[widget.itemId];
        final offline = localItem?.offlineTrickplay;
        if (offline != null && offline.tileFilesByIndex.isNotEmpty) {
          session = TrickplaySession.offline(
            itemId: widget.itemId,
            manifest: offline.manifest,
            tileFilesByIndex: offline.tileFilesByIndex,
          );
        }
      }
      session ??= await ref
          .read(jellyfinRepositoryProvider)
          .getTrickplaySession(
            widget.itemId,
            mediaSourceId: source?.mediaSourceId,
          );
      if (!mounted || _lastManifestKey != key) return;
      setState(() => _trickplay = session);
      if (session != null) {
        final dio = ref.read(jellyfinApiProvider).dio;
        final first = session.frameAtWithDuration(Duration.zero);
        unawaited(_TrickplayTileCache.prefetch(dio, first.urls));
      }
    } catch (e) {
      if (_trickplayDebugLogs) {
        debugPrint('Trickplay load failed in controls key=$key error=$e');
      }
      if (!mounted || _lastManifestKey != key) return;
      setState(() => _trickplay = null);
    }
  }

  void _prefetchAround(
    TrickplaySession session,
    Duration position,
    Duration totalDuration,
  ) {
    final dio = ref.read(jellyfinApiProvider).dio;
    final intervalMs = session.manifest.intervalMs;
    final current = session.frameAtWithDuration(
      position,
      totalDuration: totalDuration,
    );
    final prevPos = Duration(
      milliseconds: (position.inMilliseconds - intervalMs).clamp(
        0,
        totalDuration.inMilliseconds,
      ),
    );
    final nextPos = Duration(
      milliseconds: (position.inMilliseconds + intervalMs).clamp(
        0,
        totalDuration.inMilliseconds,
      ),
    );
    final prev = session.frameAtWithDuration(
      prevPos,
      totalDuration: totalDuration,
    );
    final next = session.frameAtWithDuration(
      nextPos,
      totalDuration: totalDuration,
    );
    final urls = <String>[...current.urls, ...prev.urls, ...next.urls];
    unawaited(_TrickplayTileCache.prefetch(dio, urls));
  }

  @override
  Widget build(BuildContext context) {
    final player = video_ctrl.controller(context).player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durSnap) {
            return StreamBuilder<Duration>(
              stream: player.stream.buffer,
              initialData: player.state.buffer,
              builder: (context, bufferSnap) {
                final position = posSnap.data ?? Duration.zero;
                final duration = durSnap.data ?? Duration.zero;
                final buffer = bufferSnap.data ?? Duration.zero;
                final activePercent = _isScrubbing
                    ? _scrubPercent
                    : (_hoverPercent ?? _percent(position, duration));
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AltCastSeekBar(
                          duration: duration,
                          position: position,
                          buffer: buffer,
                          value: activePercent,
                          onScrubStart: (percent) {
                            setState(() {
                              _isScrubbing = true;
                              _scrubPercent = percent;
                              _hoverPercent = null;
                            });
                            if (_trickplay != null &&
                                duration > Duration.zero) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                          onScrubUpdate: (percent) {
                            if (!_isScrubbing) return;
                            setState(() => _scrubPercent = percent);
                            if (_trickplay != null &&
                                duration > Duration.zero) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                          onScrubEnd: (percent) async {
                            final target = duration * percent;
                            setState(() {
                              _isScrubbing = false;
                              _scrubPercent = percent;
                            });
                            widget.trickplayOverlayNotifier.value = null;
                            unawaited(player.seek(target));
                          },
                          onHoverPreview: (percent) {
                            if (_isScrubbing || duration <= Duration.zero) {
                              return;
                            }
                            if (percent == null) {
                              setState(() => _hoverPercent = null);
                              widget.trickplayOverlayNotifier.value = null;
                              return;
                            }
                            setState(() => _hoverPercent = percent);
                            if (_trickplay != null) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _formatPlayerTimestamp(duration * activePercent),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Spacer(),
                            Text(
                              _formatPlayerTimestamp(duration),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  double _percent(Duration value, Duration total) {
    if (total <= Duration.zero) return 0.0;
    final p = value.inMilliseconds / total.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }
}

class _AltCastSeekBar extends StatelessWidget {
  const _AltCastSeekBar({
    required this.duration,
    required this.position,
    required this.buffer,
    required this.value,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onHoverPreview,
  });

  final Duration duration;
  final Duration position;
  final Duration buffer;
  final double value;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final ValueChanged<double?> onHoverPreview;

  @override
  Widget build(BuildContext context) {
    final inherited = MaterialVideoControlsTheme.maybeOf(context);
    final theme = inherited?.normal ?? kDefaultMaterialVideoControlsThemeData;
    final bufferPercent = duration <= Duration.zero
        ? 0.0
        : (buffer.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      margin: theme.seekBarMargin,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double fromDx(double dx) =>
              (dx / constraints.maxWidth).clamp(0.0, 1.0);

          return MouseRegion(
            onHover: (e) => onHoverPreview(fromDx(e.localPosition.dx)),
            onExit: (_) => onHoverPreview(null),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (d) =>
                  onScrubStart(fromDx(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  onScrubUpdate(fromDx(d.localPosition.dx)),
              onHorizontalDragEnd: (_) => onScrubEnd(value),
              onHorizontalDragCancel: () => onScrubEnd(value),
              onTapDown: (d) {
                final next = fromDx(d.localPosition.dx);
                onScrubStart(next);
              },
              onTapUp: (_) => onScrubEnd(value),
              onTapCancel: () => onScrubEnd(value),
              child: SizedBox(
                width: constraints.maxWidth,
                height: theme.seekBarContainerHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: constraints.maxWidth,
                      height: theme.seekBarHeight,
                      color: theme.seekBarColor,
                      child: Stack(
                        children: [
                          FractionallySizedBox(
                            widthFactor: bufferPercent,
                            child: Container(color: theme.seekBarBufferColor),
                          ),
                          FractionallySizedBox(
                            widthFactor: value,
                            child: Container(color: theme.seekBarPositionColor),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left:
                          (constraints.maxWidth - theme.seekBarThumbSize / 2) *
                          value,
                      bottom:
                          -1.0 * theme.seekBarThumbSize / 2 +
                          theme.seekBarHeight / 2,
                      child: Container(
                        width: theme.seekBarThumbSize,
                        height: theme.seekBarThumbSize,
                        decoration: BoxDecoration(
                          color: theme.seekBarThumbColor,
                          borderRadius: BorderRadius.circular(
                            theme.seekBarThumbSize / 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AltCastTrickplayPreviewBubble extends StatelessWidget {
  const AltCastTrickplayPreviewBubble({
    super.key,
    required this.session,
    required this.position,
    required this.totalDuration,
    required this.alignPercent,
  });

  final TrickplaySession session;
  final Duration position;
  final Duration totalDuration;
  final double alignPercent;

  @override
  Widget build(BuildContext context) {
    final frame = session.frameAtWithDuration(
      position,
      totalDuration: totalDuration,
    );
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTabletOrDesktop = shortestSide >= 600;
    final safeThumbWidth = frame.thumbWidth <= 0 ? 320 : frame.thumbWidth;
    final safeThumbHeight = frame.thumbHeight <= 0 ? 180 : frame.thumbHeight;
    final thumbAspect = safeThumbWidth / safeThumbHeight;
    final preferredWidth = isTabletOrDesktop ? 300.0 : 164.0;
    final minHeight = isTabletOrDesktop ? 160.0 : 92.0;
    final maxHeight = isTabletOrDesktop ? 220.0 : 132.0;
    var frameWidth = preferredWidth;
    var frameHeight = frameWidth / thumbAspect;
    if (frameHeight > maxHeight) {
      frameHeight = maxHeight;
      frameWidth = frameHeight * thumbAspect;
    } else if (frameHeight < minHeight) {
      frameHeight = minHeight;
      frameWidth = frameHeight * thumbAspect;
    }
    final tileColumns = session.manifest.tileWidth;
    final tileRows = session.manifest.tileHeight;
    final tileImageWidth = frameWidth * tileColumns;
    final safeTileRows = tileRows.clamp(1, 20);
    final tileImageHeight = frameHeight * safeTileRows;
    final xOffset = frame.tileX * frameWidth;
    final yOffset = frame.tileY * frameHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final left = ((constraints.maxWidth - frameWidth) * alignPercent).clamp(
          0.0,
          (constraints.maxWidth - frameWidth).clamp(0.0, double.infinity),
        );
        return SizedBox(
          height: frameHeight + 28,
          child: Stack(
            children: [
              Positioned(
                left: left,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: frameWidth,
                    height: frameHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: Colors.black.withValues(alpha: 0.8),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: tileImageWidth,
                              maxWidth: tileImageWidth,
                              minHeight: tileImageHeight,
                              maxHeight: tileImageHeight,
                              child: Transform.translate(
                                offset: Offset(-xOffset, -yOffset),
                                child: SizedBox(
                                  width: tileImageWidth,
                                  height: tileImageHeight,
                                  child: _FallbackNetworkImage(
                                    urls: frame.urls,
                                    width: tileImageWidth,
                                    height: tileImageHeight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            color: Colors.black.withValues(alpha: 0.62),
                            child: Text(
                              _formatPlayerTimestamp(position),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isTabletOrDesktop ? 14 : 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FallbackNetworkImage extends ConsumerStatefulWidget {
  const _FallbackNetworkImage({
    required this.urls,
    required this.width,
    required this.height,
  });

  final List<String> urls;
  final double width;
  final double height;

  @override
  ConsumerState<_FallbackNetworkImage> createState() =>
      _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends ConsumerState<_FallbackNetworkImage> {
  late Future<Uint8List?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _FallbackNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List?> _loadBytes() async {
    final dio = ref.read(jellyfinApiProvider).dio;
    for (final url in widget.urls) {
      try {
        final data = await _TrickplayTileCache.getOrFetch(dio, url);
        if (data != null && data.isNotEmpty) {
          if (_trickplayDebugLogs) {
            debugPrintSynchronously(
              'Trickplay image loaded from cache/network url=$url bytes=${data.length}',
            );
          }
          return data;
        }
        if (_trickplayDebugLogs) {
          debugPrintSynchronously('Trickplay image empty payload url=$url');
        }
      } catch (e) {
        if (_trickplayDebugLogs) {
          debugPrintSynchronously('Trickplay image failed error=$e url=$url');
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      },
    );
  }
}

class _TrickplayTileCache {
  static final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  static const int _maxEntries = 40;

  static Future<void> prefetch(Dio dio, Iterable<String> urls) async {
    final unique = <String>{...urls};
    for (final url in unique) {
      unawaited(getOrFetch(dio, url));
    }
  }

  static Future<Uint8List?> getOrFetch(Dio dio, String url) async {
    final hit = _memory.remove(url);
    if (hit != null) {
      // Reinsert to mark as most recently used.
      _memory[url] = hit;
      return hit;
    }
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _fetch(dio, url);
    _inFlight[url] = future;
    try {
      final data = await future;
      if (data != null && data.isNotEmpty) {
        _memory[url] = data;
        while (_memory.length > _maxEntries) {
          _memory.remove(_memory.keys.first);
        }
      }
      return data;
    } finally {
      _inFlight.remove(url);
    }
  }

  static Future<Uint8List?> _fetch(Dio dio, String url) async {
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (_trickplayDebugLogs) {
        debugPrintSynchronously(
          'Trickplay image failed status=${e.response?.statusCode} url=$url',
        );
      }
      return null;
    }
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
