part of '../player_material_theme.dart';

class PlayerMaterialTokens {
  const PlayerMaterialTokens({
    // Interaction timing.
    this.controlsHoverDuration = const Duration(seconds: 4),
    this.seekDoubleTapBackwardDuration = const Duration(seconds: 10),
    this.seekDoubleTapForwardDuration = const Duration(seconds: 10),
    this.seekBackwardStep = const Duration(seconds: 10),
    this.seekForwardStep = const Duration(seconds: 10),

    // Brightness & seek bar behavior.
    this.initialBrightness = 0.5,
    this.seekBarTouchTargetHeight = 48.0,
    this.seekBarHeight = 5.0,
    this.seekBarThumbSize = 18.0,

    // Top bar spacing and gesture thresholds (0..1 range).
    this.topBarButtonGap = 8.0,
    this.volumeMidThreshold = 0.5,
    this.brightnessLowThreshold = 1.0 / 3.0,
    this.brightnessHighThreshold = 2.0 / 3.0,

    // Primary playback button sizing.
    this.playPausePrimaryIconSize = 56.0,
    this.seekButtonIconSize = 44.0,
    this.playPauseDefaultIconSize = 48.0,
    this.primaryControlGap = 128.0,

    // Vertical gesture indicator layout.
    this.gestureIndicatorWidth = 54.0,
    this.gestureIndicatorHeight = 164.0,
    this.gestureIndicatorHorizontalPadding = 34.0,
    this.gestureIndicatorInnerPaddingH = 10.0,
    this.gestureIndicatorInnerPaddingV = 12.0,
    this.gestureIndicatorIconSize = 22.0,
    this.gestureIndicatorSpacing = 10.0,
    this.gestureIndicatorTrackWidth = 4.0,
    this.gestureIndicatorKnobSize = 12.0,
    this.gestureIndicatorKnobOffset = 10.0,
    this.gestureIndicatorLabelSize = 11.0,

    // Vertical gesture indicator colors/elevation.
    this.gestureIndicatorBackgroundAlpha = 0.58,
    this.gestureIndicatorBorderAlpha = 0.14,
    this.gestureIndicatorShadowAlpha = 0.36,
    this.gestureIndicatorKnobShadowAlpha = 0.34,
    this.gestureIndicatorTrackAlpha = 0.22,
    this.gestureIndicatorShadowBlur = 18.0,
    this.gestureIndicatorKnobShadowBlur = 8.0,

    // Shared title/chrome text styling.
    this.titleAlpha = 0.95,
    this.titleFontSize = 15.0,
    this.titleShadowAlpha = 0.75,
    this.titleShadowBlur = 8.0,

    // Trickplay preview sizing.
    this.previewTabletBreakpoint = 600.0,
    this.previewFallbackThumbWidth = 320.0,
    this.previewFallbackThumbHeight = 180.0,
    this.previewWidthLarge = 300.0,
    this.previewWidthSmall = 164.0,
    this.previewMinHeightLarge = 160.0,
    this.previewMinHeightSmall = 92.0,
    this.previewMaxHeightLarge = 220.0,
    this.previewMaxHeightSmall = 132.0,

    // Trickplay preview visual styling.
    this.previewCaptionHeight = 28.0,
    this.previewBorderRadius = 10.0,
    this.previewFrameBackgroundAlpha = 0.8,
    this.previewCaptionBackgroundAlpha = 0.62,
    this.previewCaptionFontSizeLarge = 14.0,
    this.previewCaptionFontSizeSmall = 11.0,
    this.previewCaptionPaddingH = 8.0,
    this.previewCaptionPaddingV = 5.0,
    this.previewTileRowsMax = 20,
    this.previewLoadingSpinnerSize = 18.0,
    this.previewLoadingSpinnerStrokeWidth = 2.0,
    this.seekGroupTimestampGap = 4.0,
    this.cacheMaxEntries = 40,
  });

  // Interaction timing.
  final Duration controlsHoverDuration;
  final Duration seekDoubleTapBackwardDuration;
  final Duration seekDoubleTapForwardDuration;
  final Duration seekBackwardStep;
  final Duration seekForwardStep;

  // Brightness & seek bar behavior.
  final double initialBrightness;
  final double seekBarTouchTargetHeight;
  final double seekBarHeight;
  final double seekBarThumbSize;

  // Top bar spacing and gesture thresholds (0..1 range).
  final double topBarButtonGap;
  final double volumeMidThreshold;
  final double brightnessLowThreshold;
  final double brightnessHighThreshold;

  // Primary playback button sizing.
  final double playPausePrimaryIconSize;
  final double seekButtonIconSize;
  final double playPauseDefaultIconSize;
  final double primaryControlGap;

  // Vertical gesture indicator layout.
  final double gestureIndicatorWidth;
  final double gestureIndicatorHeight;
  final double gestureIndicatorHorizontalPadding;
  final double gestureIndicatorInnerPaddingH;
  final double gestureIndicatorInnerPaddingV;
  final double gestureIndicatorIconSize;
  final double gestureIndicatorSpacing;
  final double gestureIndicatorTrackWidth;
  final double gestureIndicatorKnobSize;
  final double gestureIndicatorKnobOffset;
  final double gestureIndicatorLabelSize;

  // Vertical gesture indicator colors/elevation.
  final double gestureIndicatorBackgroundAlpha;
  final double gestureIndicatorBorderAlpha;
  final double gestureIndicatorShadowAlpha;
  final double gestureIndicatorKnobShadowAlpha;
  final double gestureIndicatorTrackAlpha;
  final double gestureIndicatorShadowBlur;
  final double gestureIndicatorKnobShadowBlur;

  // Shared title/chrome text styling.
  final double titleAlpha;
  final double titleFontSize;
  final double titleShadowAlpha;
  final double titleShadowBlur;

  // Trickplay preview sizing.
  final double previewTabletBreakpoint;
  final double previewFallbackThumbWidth;
  final double previewFallbackThumbHeight;
  final double previewWidthLarge;
  final double previewWidthSmall;
  final double previewMinHeightLarge;
  final double previewMinHeightSmall;
  final double previewMaxHeightLarge;
  final double previewMaxHeightSmall;
  final double previewCaptionHeight;
  final double previewBorderRadius;

  // Trickplay preview visual styling.
  final double previewFrameBackgroundAlpha;
  final double previewCaptionBackgroundAlpha;
  final double previewCaptionFontSizeLarge;
  final double previewCaptionFontSizeSmall;
  final double previewCaptionPaddingH;
  final double previewCaptionPaddingV;
  final int previewTileRowsMax;
  final double previewLoadingSpinnerSize;
  final double previewLoadingSpinnerStrokeWidth;

  // Seek row + cache policy.
  final double seekGroupTimestampGap;

  /// Maximum number of trickplay tiles kept in in-memory LRU cache.
  final int cacheMaxEntries;
}
