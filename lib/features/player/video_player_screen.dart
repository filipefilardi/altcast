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
import '../../core/utils/language.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/intro_skipper_timestamps.dart';
import '../../data/jellyfin/models/stream_source.dart';
import '../../data/jellyfin/models/episode.dart';
import '../../data/local/playback_preferences.dart';
import 'player_material_theme.dart';
import 'scrobbler.dart';
import 'widgets/next_up_card.dart';
import 'widgets/playback_error.dart';
import 'widgets/skip_chips.dart';
import 'widgets/tracks_sheet.dart';

/// Jellyfin's PositionTicks unit: 1 ms = 10000 ticks (100-ns ticks).
const _ticksPerMs = 10000;
const _resumeSeekTolerance = Duration(seconds: 2);

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
    this.nextEpisodePosterUrl,
    this.autoplayCountdown,
    this.autoplayDuration = 8,
  });

  final bool showSkipIntro;
  final bool showSkipCredits;
  final bool showNextUp;
  final Episode? nextEpisode;
  final String? nextEpisodePosterUrl;
  final int? autoplayCountdown;

  /// Total countdown length when autoplay is running — used to draw the
  /// circular progress arc on the Next Up card.
  final int autoplayDuration;
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
  Scrobbler? _scrobbler;
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
  String? _nextEpisodePosterUrl;
  bool _showNextUp = false;
  int _autoplayCountdown = 8;
  int _autoplayDuration = 8;
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

    // Use libmpv's native subtitle rasterizer for maximum format compatibility
    // (ASS/SSA styling, positioning, bitmap subtitles, etc.).
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
      nextEpisodePosterUrl: _nextEpisodePosterUrl,
      autoplayCountdown: _autoplayTimer != null ? _autoplayCountdown : null,
      autoplayDuration: _autoplayDuration,
    );
  }

  Future<void> _prepareScreenBrightnessForGestures() async {
    try {
      await ScreenBrightness().setAnimate(false);
    } catch (_) {}
  }

  Future<void> _open() async {
    try {
      // Capture providers upfront — calling `ref.read` after an await on a
      // disposed widget throws.
      final downloads = ref.read(downloadManagerProvider);
      final repo = ref.read(jellyfinRepositoryProvider);
      final api = ref.read(jellyfinApiProvider);
      // Prefer the local file if this item was downloaded — saves a server
      // round-trip and lets playback work fully offline.
      final localPath = downloads.localPath(widget.itemId);
      final StreamSource source;
      if (localPath != null) {
        source = StreamSource(
          url: Uri.file(localPath).toString(),
          isTranscoding: false,
        );
      } else {
        source = await repo.getStreamSource(widget.itemId);
      }
      if (!mounted) return;
      _sourceNotifier.value = source;
      final auth = api.dio.options.headers['Authorization'];
      await _player.open(
        Media(
          source.url,
          httpHeaders: auth is String && auth.isNotEmpty
              ? {'Authorization': auth}
              : null,
        ),
      );
      await _seekToResumePosition(widget.resumeTicks);
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

  Future<void> _seekToResumePosition(int? resumeTicks) async {
    final ticks = resumeTicks ?? 0;
    if (ticks <= 0) return;
    final target = Duration(microseconds: ticks ~/ 10);

    // Some sources (especially transcodes/HLS) may ignore an immediate seek
    // right after open. Retry briefly until playback position settles.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      await _player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final current = _player.state.position;
      if ((current - target).abs() <= _resumeSeekTolerance) {
        _lastPosition = current;
        return;
      }
    }
    _lastPosition = target;
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
    final autoSkip = ref.read(playbackPreferencesProvider).autoSkipIntroCredits;
    if (!autoSkip) {
      _introSkipperAutoTimer?.cancel();
      _introSkipperAutoTimer = null;
      _creditsSkipperAutoTimer?.cancel();
      _creditsSkipperAutoTimer = null;
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
    if (autoSkip && intro != null && playing && inIntro) {
      _introSkipperAutoTimer ??= Timer(_introSkipperAutoSkipDelay, () async {
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

    if (autoSkip && credits != null && playing && inCredits) {
      _creditsSkipperAutoTimer ??= Timer(_introSkipperAutoSkipDelay, () async {
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
    // Capture the repo upfront — `ref.read` after dispose throws.
    final repo = ref.read(jellyfinRepositoryProvider);
    var seriesId = widget.seriesId;
    var season = widget.seasonNumber;
    var episodeNum = widget.episodeNumber;

    final routingIncomplete =
        seriesId == null ||
        seriesId.isEmpty ||
        season == null ||
        episodeNum == null;
    if (routingIncomplete) {
      try {
        final ep = await repo.getEpisode(widget.itemId);
        if (!mounted) return;
        if (ep.seriesId.isEmpty ||
            ep.parentIndexNumber == null ||
            ep.indexNumber == null) {
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

    final next = await repo.getNextEpisode(
      seriesId: seriesId,
      seasonNumber: season,
      episodeNumber: episodeNum,
    );
    if (!mounted) return;
    _nextEpisode = next;
    _nextEpisodePosterUrl = next == null
        ? null
        : repo.backdropUrl(next.id, null, fallbackPrimaryTag: next.imageTag);
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
    final scrobbler = Scrobbler(
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
    final seconds = ref
        .read(playbackPreferencesProvider)
        .autoplayCountdownSeconds;
    _autoplayDuration = seconds;
    _autoplayCountdown = seconds;
    _showNextUp = true;
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
    // Restore app default orientation after leaving the landscape-only player.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildVideoControls(VideoState videoState) {
    return ValueListenableBuilder<_PlayerOverlaysSnapshot>(
      valueListenable: _overlaySnapshots,
      builder: (context, snap, _) {
        final pad = MediaQuery.paddingOf(context);
        // Lift the skip chips above the Next Up card when both are on
        // screen so they don't visually collide near the bottom-right.
        // Card is ~300 px tall (16:9 thumb + body); 224 lift puts the chip
        // comfortably above its top edge.
        final nextUpLift = (snap.showNextUp && snap.nextEpisode != null)
            ? 224.0
            : 0.0;
        final skipperBottom =
            pad.bottom + _introSkipperChipLiftFromSafeBottom + nextUpLift;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            MaterialVideoControls(videoState),
            if (snap.showSkipIntro || snap.showSkipCredits)
              Positioned(
                right: pad.right + 16,
                bottom: skipperBottom,
                child: SkipChipStack(
                  showIntro: snap.showSkipIntro,
                  showCredits: snap.showSkipCredits,
                  onSkipIntro: () => unawaited(_manualSkipIntro()),
                  onSkipCredits: () => unawaited(_manualSkipCredits()),
                ),
              ),
            if (snap.showNextUp && snap.nextEpisode != null)
              Positioned(
                right: pad.right + 16,
                bottom: pad.bottom + 16,
                child: NextUpCard(
                  episode: snap.nextEpisode!,
                  posterUrl: snap.nextEpisodePosterUrl,
                  countdownForAutoplay: snap.autoplayCountdown,
                  countdownDuration: snap.autoplayDuration,
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
            PlaybackError(error: _openError!, onClose: () => context.pop())
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
                  visible: false,
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
    // Avoid popping in the same pointer event that triggered the close action.
    // media_kit's Material seek bar may still emit onPointerUp after controls
    // teardown, which can touch a defunct BuildContext.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (context.canPop()) context.pop();
  }

  void _showTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TracksSheet(
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
