import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

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
part 'player_material_theme/tokens.dart';

const bool _trickplayDebugLogs = true;
const double kPlayerControlsBottomBarHeight = 92.0;
const double kPlayerControlsBottomBarMargin = 16.0;
const double kPlayerSeekBarHorizontalMargin = 16.0;
const double kPlayerSeekBarBottomMargin = 4.0;
const double kTrickplayPreviewLiftFromSafeBottom =
    kPlayerControlsBottomBarMargin + kPlayerControlsBottomBarHeight - 32.0;
const PlayerMaterialTokens kDefaultPlayerMaterialTokens =
    PlayerMaterialTokens();

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

/// Material mobile controls: −10s / +10s, close + CC (tracks sheet) in the top
/// bar (visible in media_kit fullscreen), **brightness on the left** and
/// **volume on the right** via vertical drag only (no extra icon buttons).
MaterialVideoControlsThemeData buildAltCastMaterialVideoControlsTheme({
  required Player player,
  required String itemId,
  required ValueListenable<StreamSource?> sourceListenable,
  required ValueNotifier<TrickplayOverlayData?> trickplayOverlayNotifier,
  required ValueListenable<double> volumeLevelListenable,
  required ValueListenable<double> brightnessLevelListenable,
  required Future<void> Function() onClosePlayer,
  required void Function(BuildContext origin) onOpenTracks,
  required void Function(BuildContext origin) onOpenSettings,
  required void Function(BuildContext origin) onOpenCast,
  required void Function(BuildContext origin) onOpenSyncPlay,
  required void Function(double value) onVolumeChanged,
  required void Function(double value) onBrightnessChanged,
  required String title,
  PlayerMaterialTokens tokens = kDefaultPlayerMaterialTokens,
}) {
  _TrickplayTileCache.configure(tokens.cacheMaxEntries);
  final screenBrightness = ScreenBrightness();
  return MaterialVideoControlsThemeData(
    // Avoid double-insetting on mobile (safe-area + internal controls bounds).
    // Keep this zero and control spacing through bar margins.
    padding: EdgeInsets.zero,
    displaySeekBar: false,
    visibleOnMount: true,
    controlsHoverDuration: tokens.controlsHoverDuration,
    // Use media_kit's built-in backdrop so dimming is perfectly synchronized
    // with the controls visibility lifecycle.
    backdropColor: const Color.fromARGB(124, 0, 0, 0),
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
    seekOnDoubleTapBackwardDuration: tokens.seekDoubleTapBackwardDuration,
    seekOnDoubleTapForwardDuration: tokens.seekDoubleTapForwardDuration,
    initialVolume: (player.state.volume / 100.0).clamp(0.0, 1.0),
    onVolumeChanged: onVolumeChanged,
    initialBrightness: tokens.initialBrightness,
    onBrightnessChanged: (v) {
      onBrightnessChanged(v);
      unawaited(_applyScreenBrightness(screenBrightness, v));
    },
    onBrightnessReset: () =>
        unawaited(_resetScreenBrightness(screenBrightness)),
    // The persistent side meters live in [AltCastPrimaryControls] so they
    // follow MaterialVideoControls' own visibility and fade lifecycle.
    volumeIndicatorBuilder: (context, value) => const SizedBox.shrink(),
    brightnessIndicatorBuilder: (context, value) => const SizedBox.shrink(),
    seekBarPositionColor: AppColors.primary,
    seekBarThumbColor: AppColors.primary,
    seekBarHeight: tokens.seekBarHeight,
    seekBarThumbSize: tokens.seekBarThumbSize,
    buttonBarButtonColor: Colors.white,
    primaryButtonBar: [
      Expanded(
        child: AltCastPrimaryControls(
          volumeLevelListenable: volumeLevelListenable,
          brightnessLevelListenable: brightnessLevelListenable,
          tokens: tokens,
        ),
      ),
    ],
    topButtonBar: [
      Expanded(
        child: SizedBox(
          height: kPlayerControlsBottomBarHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Row(
              children: [
                Builder(
                  builder: (ctx) => AltCastChromeIconButton(
                    icon: PiconsRegular.caretLeft,
                    tooltip: 'Close',
                    tokens: tokens,
                    onPressed: () => unawaited(onClosePlayer()),
                  ),
                ),
                SizedBox(width: tokens.topBarButtonGap),
                Expanded(
                  child: AltCastPlayerTitle(title: title, tokens: tokens),
                ),
                Builder(
                  builder: (ctx) => Consumer(
                    builder: (_, ref, _) {
                      final active = ref
                          .watch(syncPlayControllerProvider)
                          .isActive;
                      return AltCastChromeIconButton(
                        icon: PiconsRegular.usersThree,
                        tooltip: 'SyncPlay',
                        color: active ? AppColors.primary : null,
                        tokens: tokens,
                        onPressed: () => onOpenSyncPlay(ctx),
                      );
                    },
                  ),
                ),
                Builder(
                  builder: (ctx) => Consumer(
                    builder: (_, ref, _) {
                      final active =
                          ref.watch(activeRemoteSessionIdProvider) != null;
                      return AltCastChromeIconButton(
                        icon: PiconsRegular.screencast,
                        tooltip: 'Cast',
                        color: active ? AppColors.primary : null,
                        tokens: tokens,
                        onPressed: () => onOpenCast(ctx),
                      );
                    },
                  ),
                ),
                Builder(
                  builder: (ctx) => AltCastChromeIconButton(
                    icon: PiconsRegular.closedCaptioning,
                    tooltip: 'Audio & subtitles',
                    tokens: tokens,
                    onPressed: () => onOpenTracks(ctx),
                  ),
                ),
                Builder(
                  builder: (ctx) => AltCastChromeIconButton(
                    icon: PiconsRegular.gear,
                    tooltip: 'Playback settings',
                    tokens: tokens,
                    onPressed: () => onOpenSettings(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    // media_kit applies one buttonBarHeight to both chrome bars. The bottom
    // seek/timestamp group needs the tall slot; pin the top row inside it so
    // that spare vertical space does not push the top chrome toward center.
    topButtonBarMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    bottomButtonBar: [
      Expanded(
        child: AltCastTrickplaySeekGroup(
          itemId: itemId,
          sourceListenable: sourceListenable,
          trickplayOverlayNotifier: trickplayOverlayNotifier,
          tokens: tokens,
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
