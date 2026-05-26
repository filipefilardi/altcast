import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/material.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart'
    as video_ctrl;
import 'package:picons/picons.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/stream_source.dart';
import 'package:altcast/data/jellyfin/remote_sessions_repository.dart';
import 'package:altcast/features/remote/remote_providers.dart';
import 'package:altcast/features/syncplay/syncplay_controller.dart';

part 'player_material_theme/widgets.dart';
part 'player_material_theme/trickplay_seek_group.dart';
part 'player_material_theme/trickplay_preview.dart';
part 'player_material_theme/trickplay_tile_cache.dart';
part 'player_material_theme/helpers.dart';

const bool _trickplayDebugLogs = true;
const double kPlayerControlsBottomBarHeight = 96.0;
const double kPlayerControlsBottomBarMargin = 8.0;
const double kPlayerSeekBarHorizontalMargin = 16.0;
const double kPlayerSeekBarBottomMargin = 8.0;
const double kTrickplayPreviewLiftFromSafeBottom =
    kPlayerControlsBottomBarMargin + kPlayerControlsBottomBarHeight - 32.0;

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
    // Avoid double-insetting on mobile (safe-area + internal controls bounds).
    // Keep this zero and control spacing through bar margins.
    padding: EdgeInsets.zero,
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
    seekOnDoubleTapForwardDuration: const Duration(seconds: 10),
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
        delta: Duration(seconds: 10),
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
    topButtonBarMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      left: kPlayerSeekBarHorizontalMargin,
      right: kPlayerSeekBarHorizontalMargin,
      bottom: kPlayerControlsBottomBarMargin,
    ),
    buttonBarHeight: kPlayerControlsBottomBarHeight,
    seekBarMargin: const EdgeInsets.only(
      left: kPlayerSeekBarHorizontalMargin,
      right: kPlayerSeekBarHorizontalMargin,
      bottom: kPlayerSeekBarBottomMargin,
    ),
  );
}
