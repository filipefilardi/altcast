import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/dio_error_message.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/utils/language.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_api.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/intro_skipper_timestamps.dart';
import '../../data/jellyfin/models/stream_source.dart';
import '../../data/jellyfin/models/episode.dart';
import '../../data/local/playback_preferences.dart';
import 'player_material_theme.dart';

/// Jellyfin's PositionTicks unit: 1 ms = 10000 ticks (100-ns ticks).
const _ticksPerMs = 10000;

/// Gives time to see skip chips before we jump automatically (when enabled).
const _introSkipperAutoSkipDelay = Duration(seconds: 3);

/// Clears MaterialVideoControls (seek bar + bottom bar) so chips stay visible.
const _introSkipperChipLiftFromSafeBottom = 104.0;

/// Snapshot pushed to [ValueNotifier] so skip / next-up UI rebuilds inside
/// [MaterialVideoControls] — required because media_kit fullscreen is a
/// separate route that only contains [Video], not the screen-level [Stack].
class _PlayerOverlaysSnapshot {
  const _PlayerOverlaysSnapshot({
    this.showSkipIntro = false,
    this.showSkipCredits = false,
    this.showNextUp = false,
    this.nextEpisode,
    this.autoplayCountdown,
  });

  final bool showSkipIntro;
  final bool showSkipCredits;
  final bool showNextUp;
  final Episode? nextEpisode;
  final int? autoplayCountdown;
}

/// Full-screen video player. Routes here are entered via
/// `/play/:id?resumeTicks=N` — the optional `resumeTicks` (Jellyfin tick
/// count, 100 ns) is applied with [Player.seek] right after open.
///
/// Uses [MaterialVideoControls] with AltCast theming: −10s / +30s seek
/// buttons, brightness and volume (edge gestures + sheet sliders), and
/// automatic media_kit fullscreen (no separate fullscreen control).
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.itemId,
    this.resumeTicks,
    this.preferredAudioLang,
    this.preferredSubLang,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String itemId;

  /// Jellyfin tick count (100 ns units) — converts to a [Duration] via
  /// `microseconds = ticks ~/ 10`.
  final int? resumeTicks;

  /// ISO 639 language code chosen on the detail screen. The player picks
  /// the first matching audio track after open. `null` → leave the player's
  /// default selection alone.
  final String? preferredAudioLang;

  /// ISO 639 code for the preferred subtitle, or the literal `"off"` to
  /// explicitly disable. Matches both embedded and external subs by
  /// language. `null` → no override.
  final String? preferredSubLang;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  _Scrobbler? _scrobbler;
  Object? _openError;

  // Tracks the latest known position so we can report it on pause/stop
  // without awaiting an async getter.
  Duration _lastPosition = Duration.zero;

  // Drives the periodic /Sessions/Playing/Progress posts while playing.
  Timer? _progressTimer;

  // Subscriptions to media_kit player streams. Cancelled on dispose.
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _durationSub;
  Episode? _nextEpisode;
  bool _showNextUp = false;
  int _autoplayCountdown = 8;
  Timer? _autoplayTimer;
  Duration _mediaDuration = Duration.zero;

  IntroSkipperTimestamps? _introSkipper;
  bool _showSkipIntroChip = false;
  bool _showSkipCreditsChip = false;
  Timer? _introSkipperAutoTimer;
  Timer? _creditsSkipperAutoTimer;

  final ValueNotifier<_PlayerOverlaysSnapshot> _overlaySnapshots =
      ValueNotifier(const _PlayerOverlaysSnapshot());

  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  bool _scheduledFullscreen = false;

  /// Live source — set as soon as PlaybackInfo (or local-file resolution)
  /// completes. Exposed as a [ValueNotifier] so the tracks sheet can
  /// rebuild when the external-subs list arrives, even if it was opened
  /// during the brief interval before [_open] finishes.
  final ValueNotifier<StreamSource?> _sourceNotifier =
      ValueNotifier<StreamSource?>(null);

  /// Mirror of the currently-selected external subtitle id. Same notifier
  /// pattern so the sheet's "selected" highlight reacts immediately.
  final ValueNotifier<String?> _selectedExternalSubNotifier =
      ValueNotifier<String?>(null);

  StreamSource? get _source => _sourceNotifier.value;

  @override
  void initState() {
    super.initState();
    _player = Player();
    final useAndroidSoftwareDecode =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        ref.read(playbackPreferencesProvider).androidSoftwareVideoDecode;
    _controller = VideoController(
      _player,
      configuration: useAndroidSoftwareDecode
          ? const VideoControllerConfiguration(
              enableHardwareAcceleration: false,
            )
          : const VideoControllerConfiguration(),
    );

    // Subtitle overlay on — Jellyfin sidecar URLs carry api_key; main stream
    // auth is passed via [Media.httpHeaders] in [_open] (mpv expects structured
    // headers there — a raw `http-header-fields` string can break HTTP).
    try {
      final impl = _player.platform as dynamic;
      impl?.setProperty('sub-visibility', 'yes');
    } catch (_) {}

    // Lock to landscape while the player is on screen. Best-effort:
    // ignore platforms (web, desktop) that don't support orientation locks.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _positionSub = _player.stream.position.listen((p) => _lastPosition = p);

    // iOS: default animated brightness updates cancel each other during fast
    // vertical drags, so the OS level never settles — disable animation.
    unawaited(_prepareScreenBrightnessForGestures());

    _open();
  }

  void _publishOverlays() {
    if (!mounted) return;
    _overlaySnapshots.value = _PlayerOverlaysSnapshot(
      showSkipIntro: _showSkipIntroChip,
      showSkipCredits: _showSkipCreditsChip,
      showNextUp: _showNextUp,
      nextEpisode: _nextEpisode,
      autoplayCountdown: _autoplayTimer != null ? _autoplayCountdown : null,
    );
  }

  Future<void> _prepareScreenBrightnessForGestures() async {
    try {
      await ScreenBrightness().setAnimate(false);
    } catch (_) {}
  }

  Future<void> _open() async {
    try {
      // Prefer the local file if this item was downloaded — saves a server
      // round-trip and lets playback work fully offline.
      final localPath = ref
          .read(downloadManagerProvider)
          .localPath(widget.itemId);
      final StreamSource source;
      if (localPath != null) {
        source = StreamSource(
          url: Uri.file(localPath).toString(),
          isTranscoding: false,
        );
      } else {
        source = await ref
            .read(jellyfinRepositoryProvider)
            .getStreamSource(widget.itemId);
      }
      _sourceNotifier.value = source;
      final api = ref.read(jellyfinApiProvider);
      final auth = api.dio.options.headers['Authorization'];
      await _player.open(
        Media(
          source.url,
          httpHeaders: auth is String && auth.isNotEmpty
              ? {'Authorization': auth}
              : null,
        ),
      );
      final ticks = widget.resumeTicks ?? 0;
      if (ticks > 0) {
        final at = Duration(microseconds: ticks ~/ 10);
        await _player.seek(at);
        _lastPosition = at;
      }
      _attachScrobbler();

      // Wait until media_kit has populated the tracks lists. This is more
      // robust than a fixed delay, especially for slow network streams
      // or HLS manifests that take a moment to parse.
      for (int i = 0; i < 20; i++) {
        if (_player.state.tracks.audio.isNotEmpty ||
            _player.state.tracks.subtitle.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) _applyTrackPreferences();
      await _resolveNextEpisode();
      unawaited(_loadIntroSkipper());
      if (mounted) _tryEnterFullscreenAfterOpen();
    } catch (e) {
      if (!mounted) return;
      setState(() => _openError = e);
    }
  }

  void _tryEnterFullscreenAfterOpen() {
    if (_scheduledFullscreen || !mounted) return;
    _scheduledFullscreen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _videoKey.currentState?.enterFullscreen();
      });
    });
  }

  Future<void> _loadIntroSkipper() async {
    try {
      final timestamps = await ref
          .read(jellyfinRepositoryProvider)
          .getIntroSkipperTimestamps(widget.itemId);
      if (!mounted) return;
      _introSkipper = timestamps;
      _showSkipIntroChip = false;
      _showSkipCreditsChip = false;
      _publishOverlays();
      if (timestamps != null && mounted) {
        _syncIntroSkipperOverlay(_lastPosition);
      }
    } catch (_) {}
  }

  void _cancelIntroSkipperTimers() {
    _introSkipperAutoTimer?.cancel();
    _introSkipperAutoTimer = null;
    _creditsSkipperAutoTimer?.cancel();
    _creditsSkipperAutoTimer = null;
  }

  /// Hides Intro Skipper UI and cancels delayed auto-skip timers.
  void _clearIntroSkipperOverlay() {
    _cancelIntroSkipperTimers();
    if (!mounted) return;
    if (_showSkipIntroChip || _showSkipCreditsChip) {
      _showSkipIntroChip = false;
      _showSkipCreditsChip = false;
      _publishOverlays();
    }
  }

  Future<void> _manualSkipIntro() async {
    final intro = _introSkipper?.introduction;
    if (intro == null) return;
    _introSkipperAutoTimer?.cancel();
    _introSkipperAutoTimer = null;
    await _player.seek(intro.end);
    if (mounted) {
      _showSkipIntroChip = false;
      _publishOverlays();
    }
  }

  Future<void> _manualSkipCredits() async {
    final credits = _introSkipper?.credits;
    if (credits == null) return;
    _creditsSkipperAutoTimer?.cancel();
    _creditsSkipperAutoTimer = null;
    await _player.seek(credits.end);
    if (mounted) {
      _showSkipCreditsChip = false;
      _publishOverlays();
    }
  }

  /// Shows skip chips while playback sits inside a segment and schedules a
  /// delayed auto-jump so taps remain optional.
  void _syncIntroSkipperOverlay(Duration position) {
    if (!ref.read(playbackPreferencesProvider).autoSkipIntroCredits) {
      _clearIntroSkipperOverlay();
      return;
    }
    final data = _introSkipper;
    if (data == null) {
      _clearIntroSkipperOverlay();
      return;
    }

    final playing = _player.state.playing;
    final intro = data.introduction;
    final inIntro = intro != null && intro.contains(position);
    final credits = data.credits;
    final inCredits = credits != null && credits.contains(position);

    final nextIntroChip = intro != null && inIntro;
    final nextCreditsChip = credits != null && inCredits;
    if (nextIntroChip != _showSkipIntroChip ||
        nextCreditsChip != _showSkipCreditsChip) {
      if (mounted) {
        _showSkipIntroChip = nextIntroChip;
        _showSkipCreditsChip = nextCreditsChip;
        _publishOverlays();
      }
    }

    // Delayed auto-skip while actively playing inside each segment.
    if (intro != null && playing && inIntro) {
      _introSkipperAutoTimer ??=
          Timer(_introSkipperAutoSkipDelay, () async {
        _introSkipperAutoTimer = null;
        if (!mounted) return;
        final pos = _lastPosition;
        final i = _introSkipper?.introduction;
        if (i != null &&
            i.contains(pos) &&
            _player.state.playing &&
            ref.read(playbackPreferencesProvider).autoSkipIntroCredits) {
          await _player.seek(i.end);
          if (mounted) {
            _showSkipIntroChip = false;
            _publishOverlays();
          }
        }
      });
    } else {
      _introSkipperAutoTimer?.cancel();
      _introSkipperAutoTimer = null;
    }

    if (credits != null && playing && inCredits) {
      _creditsSkipperAutoTimer ??=
          Timer(_introSkipperAutoSkipDelay, () async {
        _creditsSkipperAutoTimer = null;
        if (!mounted) return;
        final pos = _lastPosition;
        final c = _introSkipper?.credits;
        if (c != null &&
            c.contains(pos) &&
            _player.state.playing &&
            ref.read(playbackPreferencesProvider).autoSkipIntroCredits) {
          await _player.seek(c.end);
          if (mounted) {
            _showSkipCreditsChip = false;
            _publishOverlays();
          }
        }
      });
    } else {
      _creditsSkipperAutoTimer?.cancel();
      _creditsSkipperAutoTimer = null;
    }
  }

  Future<void> _resolveNextEpisode() async {
    var seriesId = widget.seriesId;
    var season = widget.seasonNumber;
    var episodeNum = widget.episodeNumber;

    final routingIncomplete = seriesId == null ||
        seriesId.isEmpty ||
        season == null ||
        episodeNum == null;
    if (routingIncomplete) {
      try {
        final ep =
            await ref.read(jellyfinRepositoryProvider).getEpisode(widget.itemId);
        if (ep.seriesId.isEmpty ||
            ep.parentIndexNumber == null ||
            ep.indexNumber == null) {
          if (!mounted) return;
          _publishOverlays();
          return;
        }
        seriesId = ep.seriesId;
        season = ep.parentIndexNumber!;
        episodeNum = ep.indexNumber!;
      } catch (_) {
        if (!mounted) return;
        _publishOverlays();
        return;
      }
    }

    _nextEpisode = await ref.read(jellyfinRepositoryProvider).getNextEpisode(
          seriesId: seriesId,
          seasonNumber: season,
          episodeNumber: episodeNum,
        );
    if (!mounted) return;
    _publishOverlays();
  }

  void _setSubVisibility(bool visible) {
    try {
      final impl = _player.platform as dynamic;
      if (impl != null) {
        impl.setProperty('sub-visibility', visible ? 'yes' : 'no');
      }
    } catch (_) {}
  }

  /// Applies the audio/subtitle language preferences passed via /play/:id
  /// query params. No-op when neither was set, when the matching track
  /// isn't available, or after dispose.
  ///
  /// Audio: first track whose `language` matches (case-insensitive).
  /// Subtitle: `"off"` → disable. Otherwise prefer an embedded match, then
  /// fall back to an external one, then leave alone.
  void _applyTrackPreferences() {
    final wantAudio = widget.preferredAudioLang;
    if (wantAudio != null && wantAudio.isNotEmpty) {
      final tracks = _player.state.tracks.audio;
      final match = tracks.firstWhere(
        (t) =>
            (t.language ?? '').toLowerCase() == wantAudio.toLowerCase() ||
            (languageDisplay(t.language) ?? '').toLowerCase() ==
                wantAudio.toLowerCase(),
        orElse: () => AudioTrack.auto(),
      );
      if (match.id != AudioTrack.auto().id) {
        _player.setAudioTrack(match);
      }
    }

    final wantSub = widget.preferredSubLang;
    if (wantSub == null || wantSub.isEmpty) return;
    if (wantSub.toLowerCase() == 'off') {
      _selectedExternalSubNotifier.value = null;
      _player.setSubtitleTrack(SubtitleTrack.no());
      _setSubVisibility(false);
      return;
    }

    // Try embedded first.
    final embedded = _player.state.tracks.subtitle.firstWhere(
      (t) =>
          t.id != SubtitleTrack.auto().id &&
          t.id != SubtitleTrack.no().id &&
          ((t.language ?? '').toLowerCase() == wantSub.toLowerCase() ||
              (languageDisplay(t.language) ?? '').toLowerCase() ==
                  wantSub.toLowerCase()),
      orElse: () => SubtitleTrack.no(),
    );
    if (embedded.id != SubtitleTrack.no().id) {
      _selectedExternalSubNotifier.value = null;
      _player.setSubtitleTrack(embedded);
      _setSubVisibility(true);
      return;
    }

    // Then external — comes from the StreamSource we just resolved.
    final externals = _sourceNotifier.value?.externalSubtitles ?? const [];
    for (final ext in externals) {
      if ((ext.language ?? '').toLowerCase() == wantSub.toLowerCase() ||
          (languageDisplay(ext.language) ?? '').toLowerCase() ==
              wantSub.toLowerCase()) {
        _selectedExternalSubNotifier.value = ext.id;
        _player.setSubtitleTrack(
          SubtitleTrack.uri(ext.url, title: ext.title, language: ext.language),
        );
        _setSubVisibility(true);
        return;
      }
    }
  }

  /// Wires the scrobbler to media_kit streams. Reports playback to Jellyfin
  /// so resume positions, "played" state, and Continue Watching update.
  void _attachScrobbler() {
    final api = ref.read(jellyfinApiProvider);
    final scrobbler = _Scrobbler(
      api: api,
      itemId: widget.itemId,
      playMethod: _source?.playMethod ?? 'DirectStream',
      playSessionId: _source?.playSessionId,
    );
    _scrobbler = scrobbler;

    // Notify start with the resume offset (or 0).
    scrobbler.start(positionTicks: _lastPosition.inMilliseconds * _ticksPerMs);

    // Pause / unpause events + 10-second progress timer.
    _playingSub = _player.stream.playing.listen((playing) {
      _progressTimer?.cancel();
      final ticks = _lastPosition.inMilliseconds * _ticksPerMs;
      scrobbler.progress(
        positionTicks: ticks,
        isPaused: !playing,
        eventName: playing ? 'Unpause' : 'Pause',
      );
      if (playing) {
        _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          scrobbler.progress(
            positionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
            isPaused: false,
            eventName: 'TimeUpdate',
          );
        });
      }
      if (mounted) _syncIntroSkipperOverlay(_lastPosition);
    });

    // When the file finishes, fire a final stop with full position so
    // Jellyfin marks it played.
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        _cancelAutoplay();
        scrobbler.stop(
          positionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
        );
        if (_nextEpisode != null) {
          final autoplay = ref
              .read(playbackPreferencesProvider)
              .autoplayNextTvEpisode;
          if (autoplay) {
            _startAutoplay();
          } else if (mounted) {
            _showNextUp = true;
            _autoplayCountdown = 0;
            _publishOverlays();
          }
        }
      }
    });
    _durationSub = _player.stream.duration.listen((d) => _mediaDuration = d);
    _positionSub?.cancel();
    _positionSub = _player.stream.position.listen((p) {
      _lastPosition = p;
      _maybeShowNextUp();
      if (mounted) _syncIntroSkipperOverlay(p);
    });
  }

  void _maybeShowNextUp() {
    if (_nextEpisode == null || _mediaDuration <= Duration.zero) return;
    final remaining = _mediaDuration - _lastPosition;
    if (remaining <= const Duration(seconds: 30) && !_showNextUp) {
      _showNextUp = true;
      _publishOverlays();
    }
  }

  void _startAutoplay() {
    if (!mounted || _nextEpisode == null) return;
    _showNextUp = true;
    _autoplayCountdown = 8;
    _publishOverlays();
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_autoplayCountdown <= 1) {
        t.cancel();
        _playNextEpisode();
        return;
      }
      if (!mounted) return;
      _autoplayCountdown -= 1;
      _publishOverlays();
    });
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (mounted && _showNextUp) {
      _showNextUp = false;
      _publishOverlays();
    }
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next == null || !mounted) return;
    final query = <String, String>{
      if (next.seriesId.isNotEmpty) 'seriesId': next.seriesId,
      if (next.parentIndexNumber != null)
        'seasonNumber': '${next.parentIndexNumber}',
      if (next.indexNumber != null) 'episodeNumber': '${next.indexNumber}',
    };
    final uri = Uri(
      path: '/play/${next.id}',
      queryParameters: query.isEmpty ? null : query,
    );
    context.go(uri.toString());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _autoplayTimer?.cancel();
    _cancelIntroSkipperTimers();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _durationSub?.cancel();
    // Best-effort final stop so the server records where the user left off.
    _scrobbler?.stop(positionTicks: _lastPosition.inMilliseconds * _ticksPerMs);
    // Release the server-side transcoder if we were transcoding. Fire-and-
    // forget — `_player.dispose` doesn't wait for it, but we don't need to
    // either; the server times out idle encodings anyway.
    final src = _source;
    if (src != null && src.isTranscoding && src.playSessionId != null) {
      ref
          .read(jellyfinRepositoryProvider)
          .closeActiveEncoding(playSessionId: src.playSessionId!);
    }
    _player.dispose();
    _sourceNotifier.dispose();
    _selectedExternalSubNotifier.dispose();
    _overlaySnapshots.dispose();
    unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildVideoControls(VideoState videoState) {
    return ValueListenableBuilder<_PlayerOverlaysSnapshot>(
      valueListenable: _overlaySnapshots,
      builder: (context, snap, _) {
        final pad = MediaQuery.paddingOf(context);
        final nextUpLift =
            (snap.showNextUp && snap.nextEpisode != null) ? 132.0 : 0.0;
        final skipperStackBottom =
            pad.bottom + _introSkipperChipLiftFromSafeBottom + nextUpLift;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            MaterialVideoControls(videoState),
            if (snap.showSkipCredits)
              Positioned(
                left: pad.left + 16,
                right: pad.right + 16,
                bottom: skipperStackBottom,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _IntroSkipChipButton(
                    label: 'Skip credits',
                    onPressed: () => unawaited(_manualSkipCredits()),
                  ),
                ),
              ),
            if (snap.showSkipIntro)
              Positioned(
                left: pad.left + 16,
                right: pad.right + 16,
                bottom: skipperStackBottom +
                    (snap.showSkipCredits ? 52 : 0),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _IntroSkipChipButton(
                    label: 'Skip intro',
                    onPressed: () => unawaited(_manualSkipIntro()),
                  ),
                ),
              ),
            if (snap.showNextUp && snap.nextEpisode != null)
              Positioned(
                right: pad.right + 16,
                bottom: pad.bottom + 16,
                child: _NextUpCard(
                  episode: snap.nextEpisode!,
                  countdownForAutoplay: snap.autoplayCountdown,
                  onCancel: _cancelAutoplay,
                  onPlayNow: _playNextEpisode,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsTheme = buildAltCastMaterialVideoControlsTheme(
      player: _player,
      onClosePlayer: _closePlayer,
      onOpenTracks: _showTracksSheet,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_openError != null)
            _PlaybackError(error: _openError!, onClose: () => context.pop())
          else
            MaterialVideoControlsTheme(
              normal: controlsTheme,
              fullscreen: controlsTheme,
              child: Video(
                key: _videoKey,
                controller: _controller,
                controls: _buildVideoControls,
                fit: BoxFit.contain,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: true,
                  textAlign: TextAlign.center,
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0,
                    backgroundColor: Colors.black26,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const _EdgeScrim(top: true, height: 110),
          const _EdgeScrim(top: false, height: 86),
        ],
      ),
    );
  }

  /// Pops media_kit fullscreen (if active) then the player route.
  Future<void> _closePlayer() async {
    final vs = _videoKey.currentState;
    if (vs != null && vs.isFullscreen()) {
      await vs.exitFullscreen();
    }
    if (!mounted) return;
    if (context.canPop()) context.pop();
  }

  void _showTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TracksSheet(
        player: _player,
        sourceListenable: _sourceNotifier,
        selectedExternalSubListenable: _selectedExternalSubNotifier,
        onSetSubVisibility: _setSubVisibility,
        onSelectExternalSubtitle: (sub) {
          if (!mounted) return;
          _selectedExternalSubNotifier.value = sub?.id;
          if (sub == null) {
            _player.setSubtitleTrack(SubtitleTrack.no());
            _setSubVisibility(false);
          } else {
            _player.setSubtitleTrack(
              SubtitleTrack.uri(
                sub.url,
                title: sub.title,
                language: sub.language,
              ),
            );
            _setSubVisibility(true);
          }
        },
      ),
    );
  }
}

/// Netflix-style pill shown when Intro Skipper marks an intro/credits range.
class _IntroSkipChipButton extends StatelessWidget {
  const _IntroSkipChipButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.92),
          foregroundColor: AppColors.primary,
          elevation: 6,
          shadowColor: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
    );
  }
}

class _NextUpCard extends StatelessWidget {
  const _NextUpCard({
    required this.episode,
    required this.countdownForAutoplay,
    required this.onCancel,
    required this.onPlayNow,
  });

  final Episode episode;

  /// When non-null and positive, the primary button shows a live countdown
  /// and autoplay is running. When null, only manual "Play next" is offered.
  final int? countdownForAutoplay;
  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  @override
  Widget build(BuildContext context) {
    final c = countdownForAutoplay;
    final playCta = (c != null && c > 0) ? 'Play now ($c)' : 'Play next';
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Next Up', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            episode.shortLabel.isEmpty
                ? episode.name
                : '${episode.shortLabel} • ${episode.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              const Spacer(),
              FilledButton(
                onPressed: onPlayNow,
                child: Text(playCta),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim({required this.top, required this.height});

  final bool top;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: IgnorePointer(
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: top ? 0.55 : 0.45),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the audio and subtitle tracks the [Player] has
/// detected. Tapping a row tells media_kit to switch tracks and pops the
/// sheet. The selected row is highlighted via a check mark.
///
/// We watch [Player.stream.tracks] / [Player.stream.track] so the list and
/// selection stay live: e.g. an HLS stream that adds tracks mid-playback
/// will show up automatically the next time the sheet is opened (or while
/// it's open, since [StreamBuilder] rebuilds).
class _TracksSheet extends StatelessWidget {
  const _TracksSheet({
    required this.player,
    required this.sourceListenable,
    required this.selectedExternalSubListenable,
    required this.onSelectExternalSubtitle,
    required this.onSetSubVisibility,
  });

  final Player player;

  /// Live source — driven by a [ValueNotifier] in the player screen so the
  /// external-subs list refreshes if the sheet opened *before* PlaybackInfo
  /// finished resolving (small but real timing window).
  final ValueListenable<StreamSource?> sourceListenable;

  /// Live external-sub selection. Same pattern.
  final ValueListenable<String?> selectedExternalSubListenable;

  final ValueChanged<ExternalSubtitle?> onSelectExternalSubtitle;
  final ValueChanged<bool> onSetSubVisibility;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, tracksSnap) {
          return StreamBuilder<Track>(
            stream: player.stream.track,
            initialData: player.state.track,
            builder: (context, currentSnap) {
              return ValueListenableBuilder<StreamSource?>(
                valueListenable: sourceListenable,
                builder: (context, source, _) {
                  return ValueListenableBuilder<String?>(
                    valueListenable: selectedExternalSubListenable,
                    builder: (context, selectedExternalSubId, child) {
                      final tracks = tracksSnap.data ?? player.state.tracks;
                      final current = currentSnap.data ?? player.state.track;
                      final externalSubs =
                          source?.externalSubtitles ?? const [];
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _AudioSection(
                                player: player,
                                tracks: tracks.audio,
                                current: current.audio,
                              ),
                              const SizedBox(height: 16),
                              _SubtitleSection(
                                player: player,
                                tracks: tracks.subtitle,
                                current: current.subtitle,
                                externalSubtitles: externalSubs,
                                selectedExternalSubId: selectedExternalSubId,
                                onSelectExternalSubtitle:
                                    onSelectExternalSubtitle,
                                onSetSubVisibility: onSetSubVisibility,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AudioSection extends StatelessWidget {
  const _AudioSection({
    required this.player,
    required this.tracks,
    required this.current,
  });

  final Player player;
  final List<AudioTrack> tracks;
  final AudioTrack current;

  @override
  Widget build(BuildContext context) {
    // Drop the synthetic auto/no entries — for audio we always have a real
    // track playing, so showing "Auto" is just noise.
    final real = tracks
        .where(
          (t) => t.id != AudioTrack.auto().id && t.id != AudioTrack.no().id,
        )
        .toList();
    if (real.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Audio'),
        for (final t in real)
          _TrackRow(
            label: _audioLabel(t),
            selected: t.id == current.id,
            onTap: () {
              player.setAudioTrack(t);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  String _audioLabel(AudioTrack t) => _trackDisplayLabel(
    title: t.title,
    language: t.language,
    fallbackId: t.id,
  );
}

class _SubtitleSection extends StatelessWidget {
  const _SubtitleSection({
    required this.player,
    required this.tracks,
    required this.current,
    required this.externalSubtitles,
    required this.selectedExternalSubId,
    required this.onSelectExternalSubtitle,
    required this.onSetSubVisibility,
  });

  final Player player;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack current;
  final List<ExternalSubtitle> externalSubtitles;
  final String? selectedExternalSubId;
  final ValueChanged<ExternalSubtitle?> onSelectExternalSubtitle;
  final ValueChanged<bool> onSetSubVisibility;

  @override
  Widget build(BuildContext context) {
    final embedded = tracks
        .where(
          (t) =>
              t.id != SubtitleTrack.auto().id && t.id != SubtitleTrack.no().id,
        )
        .toList();
    final hasExternal = selectedExternalSubId != null;
    final isOff = current.id == SubtitleTrack.no().id && !hasExternal;
    final hasAny = embedded.isNotEmpty || externalSubtitles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Subtitles'),
        _TrackRow(
          label: 'Off',
          selected: isOff,
          onTap: () {
            onSelectExternalSubtitle(null);
            player.setSubtitleTrack(SubtitleTrack.no());
            onSetSubVisibility(false);
            Navigator.of(context).pop();
          },
        ),
        if (!hasAny)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'No subtitle tracks available.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ),
        for (final t in embedded)
          _TrackRow(
            label: _embeddedLabel(t),
            selected: !hasExternal && !isOff && t.id == current.id,
            onTap: () {
              // Picking an embedded track clears any external selection.
              onSelectExternalSubtitle(null);
              player.setSubtitleTrack(t);
              onSetSubVisibility(true);
              Navigator.of(context).pop();
            },
          ),
        for (final sub in externalSubtitles)
          _TrackRow(
            label: '${_externalLabel(sub)} (external)',
            selected: hasExternal && sub.id == selectedExternalSubId,
            onTap: () {
              onSelectExternalSubtitle(sub);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  String _embeddedLabel(SubtitleTrack t) => _trackDisplayLabel(
    title: t.title,
    language: t.language,
    fallbackId: t.id,
  );

  String _externalLabel(ExternalSubtitle sub) {
    return _trackDisplayLabel(
      title: sub.title,
      language: sub.language,
      fallbackId: sub.codec ?? 'subs',
    );
  }
}

/// Builds a friendly label for an audio/subtitle track.
///
/// Priority: server-provided title → ISO 639 → raw language code → "Track {id}".
/// Returns the placeholder for empty everything so the row is never blank.
String _trackDisplayLabel({
  required String? title,
  required String? language,
  required String fallbackId,
}) {
  final t = title?.trim();
  if (t != null && t.isNotEmpty) {
    // If the title already encodes the language (mpv often emits "English (eng)"),
    // skip the redundant trailing code.
    final mapped = languageDisplay(language);
    if (mapped != null && t.toLowerCase() != mapped.toLowerCase()) {
      return '$t · $mapped';
    }
    return t;
  }
  final mapped = languageDisplay(language);
  if (mapped != null) return mapped;
  // Last-resort: a normalised raw code, never the literal "und".
  final raw = language?.trim();
  if (raw != null && raw.isNotEmpty && raw.toLowerCase() != 'und') {
    return raw;
  }
  return fallbackId.isEmpty ? 'Track' : 'Track $fallbackId';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => AppGradients.accent.createShader(bounds),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.surfaceHighlight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Posts playback events to Jellyfin's `/Sessions/Playing*` endpoints so
/// resume positions, watched-state, and Continue Watching stay in sync.
///
/// All posts are best-effort: failures are swallowed because scrobbling
/// must never crash playback. Tied 1-to-1 with a [VideoPlayerScreen]
/// instance — there's no global scrobbler today (unlike AltSound, where
/// audio plays outside the now-playing screen).
class _Scrobbler {
  _Scrobbler({
    required this.api,
    required this.itemId,
    required this.playMethod,
    this.playSessionId,
  });

  final JellyfinApi api;
  final String itemId;

  /// `'DirectStream'` or `'Transcode'` — comes from the negotiated
  /// [StreamSource]. Some Jellyfin housekeeping (e.g. transcoder cleanup
  /// on stop) keys off this value.
  final String playMethod;

  final String? playSessionId;

  Future<void> start({required int positionTicks}) {
    return _post('/Sessions/Playing', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      'IsPaused': false,
      'PlayMethod': playMethod,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> progress({
    required int positionTicks,
    required bool isPaused,
    required String eventName,
  }) {
    return _post('/Sessions/Playing/Progress', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      'IsPaused': isPaused,
      'EventName': eventName,
      'PlayMethod': playMethod,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> stop({required int positionTicks}) {
    return _post('/Sessions/Playing/Stopped', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    if (api.session == null) return;
    try {
      await api.dio.post<dynamic>(path, data: body);
    } catch (_) {
      // Swallow: scrobbling is best-effort.
    }
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.error, required this.onClose});
  final Object error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Playback failed',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              userFacingNetworkMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onClose, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
