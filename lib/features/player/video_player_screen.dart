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
import '../../data/downloads/downloaded_item.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/intro_skipper_timestamps.dart';
import '../../data/jellyfin/models/remote_session.dart';
import '../../data/jellyfin/models/syncplay.dart';
import '../../data/jellyfin/models/stream_source.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';
import '../../data/jellyfin/models/episode.dart';
import '../../data/local/playback_preferences.dart';
import '../remote/remote_providers.dart';
import '../remote/remote_sessions_sheet.dart';
import '../syncplay/syncplay_controller.dart';
import '../syncplay/syncplay_sheet.dart';
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

enum _PlayerControlOverlay { none, settings, subtitleOffset }

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
    this.preferredSubIndex,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.syncPlayStartPlaying,
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

  /// Jellyfin media stream index from the detail subtitle picker. Used to
  /// disambiguate multiple subtitle streams with the same language.
  final int? preferredSubIndex;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool? syncPlayStartPlaying;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  Scrobbler? _scrobbler;
  Object? _openError;
  String _playerTitle = '';
  bool _isReloadingSource = false;
  double _playbackRate = 1.0;
  Duration _subtitleOffset = Duration.zero;
  final ValueNotifier<_PlayerControlOverlay> _controlOverlayNotifier =
      ValueNotifier(_PlayerControlOverlay.none);

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
  bool _landscapeOrientation = true;
  bool _applyingSyncPlayCommand = false;
  bool _applyingRemoteCastState = false;
  bool _playerReadyForCastMirror = false;
  double? _volumeBeforeCastMirror;
  Timer? _castVolumeDebounce;
  DateTime? _lastRemoteCastSeekAt;
  DateTime? _lastRemoteControlSeekSentAt;
  int _lastSyncQueueSerial = 0;
  int _lastSyncCommandSerial = 0;
  String? _lastSyncCommandKey;
  DateTime? _lastSyncCommandAt;
  DateTime? _lastSyncSeekSentAt;

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
  final ValueNotifier<TrickplayOverlayData?> _trickplayOverlayNotifier =
      ValueNotifier<TrickplayOverlayData?>(null);

  StreamSource? get _source => _sourceNotifier.value;

  @override
  void initState() {
    super.initState();
    // Keep subtitle rendering in Flutter for consistent behavior across
    // Android, iOS, and desktop. Native mpv/libass rendering needs platform
    // specific font setup on Android and can diverge between devices.
    _player = Player(configuration: const PlayerConfiguration(libass: false));
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

    // Lock to landscape while the player is on screen. Best-effort:
    // ignore platforms (web, desktop) that don't support orientation locks.
    _applyPlayerOrientation(landscape: true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _positionSub = _player.stream.position.listen((p) => _lastPosition = p);

    // iOS: default animated brightness updates cancel each other during fast
    // vertical drags, so the OS level never settles — disable animation.
    unawaited(_prepareScreenBrightnessForGestures());

    unawaited(_loadPlayerTitle());
    final castActiveOnOpen = ref.read(activeRemoteSessionIdProvider) != null;
    _open(play: widget.syncPlayStartPlaying ?? !castActiveOnOpen);
  }

  Future<void> _loadPlayerTitle() async {
    final localTitle = _buildOfflinePlayerTitle();
    if (localTitle != null && localTitle.isNotEmpty && mounted) {
      setState(() => _playerTitle = localTitle);
    }
    try {
      final title = await ref
          .read(jellyfinRepositoryProvider)
          .getItemDisplayTitle(widget.itemId);
      if (!mounted) return;
      setState(() => _playerTitle = title);
    } catch (_) {}
  }

  String? _buildOfflinePlayerTitle() {
    final localItem = ref.read(downloadManagerProvider).items[widget.itemId];
    if (localItem == null) return null;

    if (localItem.kind == DownloadedItemKind.episode) {
      final seriesName = localItem.seriesName?.trim();
      final episodeName = localItem.name.trim();
      final number = localItem.episodeLabel;
      final titlePart = episodeName.isEmpty ? null : episodeName;
      final parts = <String>[
        if (seriesName != null && seriesName.isNotEmpty) seriesName,
        if (number?.isNotEmpty ?? false) number!,
        if (titlePart?.isNotEmpty ?? false) titlePart!,
      ];
      if (parts.isEmpty) return null;
      return parts.join(' · ');
    }

    final name = localItem.name.trim();
    if (name.isEmpty) return null;
    final year = localItem.year;
    return year == null ? name : '$name ($year)';
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

  void _applyPlayerOrientation({required bool landscape}) {
    _landscapeOrientation = landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  void _togglePlayerOrientation() {
    _applyPlayerOrientation(landscape: !_landscapeOrientation);
  }

  Future<void> _open({Duration? startPosition, bool play = true}) async {
    try {
      _playerReadyForCastMirror = false;
      if (mounted && _openError != null) {
        setState(() => _openError = null);
      }
      // Capture providers upfront — calling `ref.read` after an await on a
      // disposed widget throws.
      final downloads = ref.read(downloadManagerProvider);
      final repo = ref.read(jellyfinRepositoryProvider);
      final api = ref.read(jellyfinApiProvider);
      final quality = ref.read(playbackPreferencesProvider).streamingQuality;
      // Prefer the local file if this item was downloaded — saves a server
      // round-trip and lets playback work fully offline.
      final localItem = downloads.items[widget.itemId];
      final localPath = localItem?.filePath;
      final StreamSource source;
      if (localPath != null) {
        source = StreamSource(
          url: Uri.file(localPath).toString(),
          isTranscoding: false,
          externalSubtitles: [
            for (final sub in localItem?.externalSubtitles ?? const [])
              ExternalSubtitle(
                id: sub.id,
                url: Uri.file(sub.filePath).toString(),
                streamIndex: sub.streamIndex,
                title: sub.title,
                language: sub.language,
                codec: sub.codec,
              ),
          ],
        );
      } else {
        source = await repo.getStreamSource(widget.itemId, quality: quality);
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
        play: play,
      );
      await _seekToStartPosition(startPosition ?? _resumePositionFromRoute());
      await _applyPlaybackRate(_playbackRate);
      await _applySubtitleOffset(_subtitleOffset);
      _attachScrobbler();
      _playerReadyForCastMirror = true;
      await _publishSyncPlayOpenIfNeeded(isPlaying: play);

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
      _playerReadyForCastMirror = false;
      if (!mounted) return;
      setState(() => _openError = e);
    }
  }

  Duration _resumePositionFromRoute() {
    final ticks = widget.resumeTicks ?? 0;
    if (ticks <= 0) return Duration.zero;
    return Duration(microseconds: ticks ~/ 10);
  }

  Future<void> _seekToStartPosition(Duration target) async {
    if (target <= Duration.zero) return;

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
    final offline = _offlineIntroSkipper();
    if (offline != null && offline.hasAny) {
      _introSkipper = offline;
      _showSkipIntroChip = false;
      _showSkipCreditsChip = false;
      _publishOverlays();
      if (mounted) {
        _syncIntroSkipperOverlay(_lastPosition);
      }
      return;
    }
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

  IntroSkipperTimestamps? _offlineIntroSkipper() {
    final local = ref.read(downloadManagerProvider).items[widget.itemId];
    if (local == null) return null;
    final introStart = _ticksToDuration(local.introStartTicks);
    final introEnd = _ticksToDuration(local.introEndTicks);
    final creditsStart = _ticksToDuration(local.creditsStartTicks);
    final creditsEnd = _ticksToDuration(local.creditsEndTicks);
    return IntroSkipperTimestamps(
      introduction: introStart != null &&
              introEnd != null &&
              introEnd > introStart
          ? IntroSkipperRange(start: introStart, end: introEnd)
          : null,
      credits: creditsStart != null &&
              creditsEnd != null &&
              creditsEnd > creditsStart
          ? IntroSkipperRange(start: creditsStart, end: creditsEnd)
          : null,
    );
  }

  Duration? _ticksToDuration(int? ticks) {
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: ticks ~/ 10);
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
    final offlineNext = _resolveOfflineNextEpisode();
    if (offlineNext != null) {
      _nextEpisode = offlineNext;
      _nextEpisodePosterUrl = null;
      _publishOverlays();
      return;
    }

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

  Episode? _resolveOfflineNextEpisode() {
    final downloads = ref.read(downloadManagerProvider).items;
    final current = downloads[widget.itemId];
    if (current == null || current.kind != DownloadedItemKind.episode) {
      return null;
    }
    final seriesId = current.seriesId;
    final season = current.seasonNumber;
    final episode = current.episodeNumber;
    if (seriesId == null || season == null || episode == null) return null;

    final candidates = downloads.values
        .where(
          (item) =>
              item.kind == DownloadedItemKind.episode &&
              item.seriesId == seriesId &&
              item.seasonNumber != null &&
              item.episodeNumber != null,
        )
        .toList(growable: false);
    candidates.sort((a, b) {
      final seasonDiff = a.seasonNumber!.compareTo(b.seasonNumber!);
      if (seasonDiff != 0) return seasonDiff;
      return a.episodeNumber!.compareTo(b.episodeNumber!);
    });

    for (final candidate in candidates) {
      final afterCurrentSeason = candidate.seasonNumber! > season;
      final sameSeasonNextEpisode =
          candidate.seasonNumber == season && candidate.episodeNumber! > episode;
      if (afterCurrentSeason || sameSeasonNextEpisode) {
        return Episode(
          id: candidate.id,
          name: candidate.name,
          seriesId: candidate.seriesId ?? '',
          seriesName: candidate.seriesName,
          parentIndexNumber: candidate.seasonNumber,
          indexNumber: candidate.episodeNumber,
          runTime: candidate.runTime,
          imageTag: candidate.imageTag,
        );
      }
    }
    return null;
  }

  void _setSubVisibility(bool _) {
    // Track selection controls the Flutter subtitle overlay. Keep mpv's native
    // subtitle compositing disabled so subtitles render the same on every
    // platform and do not duplicate with the Flutter layer.
    try {
      final impl = _player.platform as dynamic;
      if (impl != null) {
        impl.setProperty('sub-visibility', 'no');
      }
    } catch (_) {}
  }

  Future<void> _applyPlaybackRate(double rate) async {
    _playbackRate = rate;
    await _player.setRate(rate);
  }

  Future<void> _applySubtitleOffset(Duration offset) async {
    _subtitleOffset = offset;
    try {
      final impl = _player.platform as dynamic;
      if (impl != null) {
        final seconds = offset.inMilliseconds / 1000.0;
        await impl.setProperty('sub-delay', seconds.toStringAsFixed(3));
      }
    } catch (_) {}
  }

  Future<void> _reloadStreamForQualityChange() async {
    if (_isReloadingSource) return;
    setState(() => _isReloadingSource = true);
    final position = _lastPosition;
    final wasPlaying = _player.state.playing;
    _stopPlaybackReporting();
    await _closeActiveEncoding(_source);
    unawaited(
      _scrobbler?.stop(positionTicks: position.inMilliseconds * _ticksPerMs) ??
          Future<void>.value(),
    );
    try {
      await _open(startPosition: position, play: wasPlaying);
    } finally {
      if (mounted) setState(() => _isReloadingSource = false);
    }
  }

  void _stopPlaybackReporting() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _playingSub?.cancel();
    _playingSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _durationSub?.cancel();
    _durationSub = null;
  }

  Future<void> _closeActiveEncoding(StreamSource? src) async {
    if (src != null && src.isTranscoding && src.playSessionId != null) {
      await ref
          .read(jellyfinRepositoryProvider)
          .closeActiveEncoding(playSessionId: src.playSessionId!);
    }
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
    final wantSubIndex = widget.preferredSubIndex;
    if ((wantSub == null || wantSub.isEmpty) && wantSubIndex == null) return;
    if (wantSub != null && wantSub.toLowerCase() == 'off') {
      _selectedExternalSubNotifier.value = null;
      _player.setSubtitleTrack(SubtitleTrack.no());
      _setSubVisibility(false);
      return;
    }

    if (wantSubIndex != null) {
      final externals = _sourceNotifier.value?.externalSubtitles ?? const [];
      for (final ext in externals) {
        if (ext.streamIndex == wantSubIndex) {
          _selectedExternalSubNotifier.value = ext.id;
          _player.setSubtitleTrack(
            SubtitleTrack.uri(
              ext.url,
              title: ext.title,
              language: ext.language,
            ),
          );
          _setSubVisibility(true);
          return;
        }
      }

      final embedded = _player.state.tracks.subtitle.firstWhere(
        (t) =>
            t.id != SubtitleTrack.auto().id &&
            t.id != SubtitleTrack.no().id &&
            _subtitleTrackMatchesStreamIndex(t, wantSubIndex),
        orElse: () => SubtitleTrack.no(),
      );
      if (embedded.id != SubtitleTrack.no().id) {
        _selectedExternalSubNotifier.value = null;
        _player.setSubtitleTrack(embedded);
        _setSubVisibility(true);
        return;
      }
    }

    if (wantSub == null || wantSub.isEmpty) return;

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

  bool _subtitleTrackMatchesStreamIndex(SubtitleTrack track, int index) {
    if (track.id == '$index') return true;
    return int.tryParse(track.id) == index;
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
      if (_remoteCastMirrorActive) {
        if (mounted) _syncIntroSkipperOverlay(_lastPosition);
        return;
      }
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
      if (!_applyingSyncPlayCommand && !_remoteCastMirrorActive) {
        unawaited(_publishSyncPlayPlaying(playing));
      }
      if (mounted) _syncIntroSkipperOverlay(_lastPosition);
    });

    // When the file finishes, fire a final stop with full position so
    // Jellyfin marks it played.
    _completedSub = _player.stream.completed.listen((completed) {
      if (_remoteCastMirrorActive) return;
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
      final previous = _lastPosition;
      _lastPosition = p;
      if (_remoteCastMirrorActive && !_applyingRemoteCastState) {
        unawaited(_maybePublishRemoteCastSeek(previous, p));
      }
      if (!_applyingSyncPlayCommand && !_remoteCastMirrorActive) {
        unawaited(_maybePublishSyncPlaySeek(previous, p));
      }
      if (!_remoteCastMirrorActive) _maybeShowNextUp();
      if (mounted) _syncIntroSkipperOverlay(p);
    });
  }

  bool get _syncPlayActive =>
      ref.read(syncPlayControllerProvider).activeGroup != null;

  bool get _remoteCastMirrorActive =>
      _applyingRemoteCastState || _volumeBeforeCastMirror != null;

  void _handlePlayerVolumeChanged(double value) {
    final remoteSessionId = ref.read(activeRemoteSessionIdProvider);
    if (remoteSessionId == null) {
      unawaited(_player.setVolume(value * 100.0));
      return;
    }

    _castVolumeDebounce?.cancel();
    _castVolumeDebounce = Timer(const Duration(milliseconds: 90), () {
      unawaited(
        ref
            .read(remoteSessionsRepositoryProvider)
            .setVolume(remoteSessionId, (value * 100).round()),
      );
    });
  }

  Future<void> _maybePublishRemoteCastSeek(
    Duration previous,
    Duration position,
  ) async {
    if (previous <= Duration.zero) return;
    final jump = (position - previous).abs();
    if (jump < const Duration(milliseconds: 900)) return;
    final sessionId = ref.read(activeRemoteSessionIdProvider);
    if (sessionId == null) return;
    final now = DateTime.now();
    final lastSentAt = _lastRemoteControlSeekSentAt;
    if (lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastRemoteControlSeekSentAt = now;
    _lastRemoteCastSeekAt = now;
    try {
      await ref
          .read(remoteSessionsRepositoryProvider)
          .seek(sessionId, position);
    } catch (_) {}
  }

  Future<void> _publishSyncPlayPlaying(bool playing) async {
    if (!_syncPlayActive) return;
    final state = ref.read(syncPlayControllerProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);
    if (state.currentItemId != widget.itemId) {
      await controller.setCurrentVideo(
        widget.itemId,
        startPosition: _lastPosition,
      );
    }
    if (playing) {
      await controller.unpause();
    } else {
      await controller.pause();
    }
  }

  Future<void> _maybePublishSyncPlaySeek(
    Duration previous,
    Duration position,
  ) async {
    if (!_syncPlayActive || previous <= Duration.zero) return;
    final jump = (position - previous).abs();
    if (jump < const Duration(seconds: 3)) return;
    final now = DateTime.now();
    final lastSentAt = _lastSyncSeekSentAt;
    if (lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(milliseconds: 700)) {
      return;
    }
    _lastSyncSeekSentAt = now;
    await ref.read(syncPlayControllerProvider.notifier).seek(position);
  }

  Future<void> _publishSyncPlayOpenIfNeeded({required bool isPlaying}) async {
    if (!_syncPlayActive) return;
    final state = ref.read(syncPlayControllerProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);
    if (state.currentItemId != widget.itemId) {
      await controller.setCurrentVideo(
        widget.itemId,
        startPosition: _lastPosition,
      );
      if (!isPlaying) {
        await controller.pause();
      }
      return;
    }
    await controller.ready(position: _lastPosition, isPlaying: isPlaying);
  }

  void _handleActiveRemoteSessionChange(
    AsyncValue<RemoteSession?>? previous,
    AsyncValue<RemoteSession?> next,
  ) {
    final session = next.value;
    if (session == null || !session.isPlayingSomething) {
      unawaited(_stopRemoteCastMirror());
      return;
    }

    final remoteItemId = session.nowPlayingItemId;
    if (remoteItemId == null || remoteItemId.isEmpty) {
      unawaited(_stopRemoteCastMirror());
      return;
    }

    if (remoteItemId != widget.itemId) {
      final position = session.estimatedPosition() ?? Duration.zero;
      context.go(
        Uri(
          path: '/play/$remoteItemId',
          queryParameters: {
            'resumeTicks': '${position.inMilliseconds * _ticksPerMs}',
          },
        ).toString(),
      );
      return;
    }

    unawaited(_mirrorRemoteCastSession(session));
  }

  Future<void> _mirrorRemoteCastSession(RemoteSession session) async {
    if (!_playerReadyForCastMirror || !mounted) return;
    _applyingRemoteCastState = true;
    try {
      _volumeBeforeCastMirror ??= _player.state.volume;
      if (_player.state.volume > 0) {
        await _player.setVolume(0);
      }

      final remotePosition = session.estimatedPosition();
      if (remotePosition != null) {
        final drift = (_lastPosition - remotePosition).abs();
        final now = DateTime.now();
        final lastSeekAt = _lastRemoteCastSeekAt;
        final minSeekInterval = session.isPaused
            ? const Duration(milliseconds: 350)
            : const Duration(seconds: 3);
        final seekThreshold = session.isPaused
            ? const Duration(milliseconds: 450)
            : const Duration(seconds: 3);
        final canSeek =
            lastSeekAt == null || now.difference(lastSeekAt) >= minSeekInterval;
        if (drift > seekThreshold && canSeek) {
          _lastRemoteCastSeekAt = now;
          await _player.seek(remotePosition);
        }
      }

      if (session.isPaused) {
        if (_player.state.playing) await _player.pause();
      } else {
        if (!_player.state.playing) await _player.play();
      }
    } finally {
      _applyingRemoteCastState = false;
    }
  }

  Future<void> _stopRemoteCastMirror() async {
    final restoreVolume = _volumeBeforeCastMirror;
    if (restoreVolume == null) return;
    _volumeBeforeCastMirror = null;
    _lastRemoteCastSeekAt = null;
    _applyingRemoteCastState = true;
    try {
      if (_player.state.playing) {
        await _player.pause();
      }
      await _player.setVolume(restoreVolume);
    } finally {
      _applyingRemoteCastState = false;
    }
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
    _castVolumeDebounce?.cancel();
    _cancelIntroSkipperTimers();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _durationSub?.cancel();
    // Best-effort final stop so the server records where the user left off.
    if (!_remoteCastMirrorActive) {
      _scrobbler?.stop(
        positionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
      );
    }
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
    _trickplayOverlayNotifier.dispose();
    _overlaySnapshots.dispose();
    _controlOverlayNotifier.dispose();
    unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    // Restore app default orientation after leaving the landscape-only player.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
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
            ValueListenableBuilder<_PlayerControlOverlay>(
              valueListenable: _controlOverlayNotifier,
              builder: (context, overlay, _) {
                if (overlay == _PlayerControlOverlay.none) {
                  return const SizedBox.shrink();
                }
                final size = MediaQuery.sizeOf(context);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _hideControlOverlay,
                      ),
                    ),
                    if (overlay == _PlayerControlOverlay.settings)
                      Positioned(
                        top: pad.top + 58,
                        right: pad.right + 12,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: size.width < 380 ? size.width - 24 : 280,
                          ),
                          child: _PlaybackSettingsOverlay(
                            initialRate: _playbackRate,
                            initialSubtitleOffset: _subtitleOffset,
                            onRateChanged: _applyPlaybackRate,
                            onQualityChanged: _reloadStreamForQualityChange,
                            onOpenSubtitleOffset: _showSubtitleOffsetOverlay,
                          ),
                        ),
                      ),
                    if (overlay == _PlayerControlOverlay.subtitleOffset)
                      Positioned(
                        top: pad.top + 58,
                        left: pad.left + 20,
                        right: pad.right + 20,
                        child: _SubtitleOffsetOverlay(
                          initialSubtitleOffset: _subtitleOffset,
                          onSubtitleOffsetChanged: _applySubtitleOffset,
                        ),
                      ),
                  ],
                );
              },
            ),
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
            ValueListenableBuilder<TrickplayOverlayData?>(
              valueListenable: _trickplayOverlayNotifier,
              builder: (context, trickplay, _) {
                if (trickplay == null) return const SizedBox.shrink();
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: pad.bottom + 100,
                  child: IgnorePointer(
                    child: AltCastTrickplayPreviewBubble(
                      session: trickplay.session,
                      position: trickplay.position,
                      totalDuration: trickplay.totalDuration,
                      alignPercent: trickplay.alignPercent,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncPlayState>(
      syncPlayControllerProvider,
      _handleSyncPlayStateChange,
    );
    ref.listen<AsyncValue<RemoteSession?>>(
      activeRemoteSessionProvider,
      _handleActiveRemoteSessionChange,
    );
    final controlsTheme = buildAltCastMaterialVideoControlsTheme(
      player: _player,
      itemId: widget.itemId,
      sourceListenable: _sourceNotifier,
      trickplayOverlayNotifier: _trickplayOverlayNotifier,
      onClosePlayer: _closePlayer,
      onOpenTracks: _showTracksSheet,
      onOpenSettings: _togglePlaybackSettings,
      onOpenCast: _showCastSheet,
      onOpenSyncPlay: _showSyncPlaySheet,
      onRotateOrientation: _togglePlayerOrientation,
      onVolumeChanged: _handlePlayerVolumeChanged,
      title: _playerTitle,
    );
    final playbackPrefs = ref.watch(playbackPreferencesProvider);
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final isTabletClass = shortestSide >= 600;
    final subtitleHorizontalPadding = isTabletClass ? 40.0 : 24.0;
    final baseBottomPadding =
        (isTabletClass ? 96.0 : 44.0) + mediaQuery.padding.bottom;
    final subtitleBottomPadding =
        (baseBottomPadding + playbackPrefs.subtitleBottomInset).clamp(
          16.0,
          220.0,
        );
    final baseSubtitleFontSize = isTabletClass ? 32.0 : 24.0;
    final subtitleFontSize =
        (baseSubtitleFontSize * playbackPrefs.subtitleFontScale).clamp(
          16.0,
          56.0,
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
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  visible: true,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  padding: EdgeInsets.fromLTRB(
                    subtitleHorizontalPadding,
                    0,
                    subtitleHorizontalPadding,
                    subtitleBottomPadding,
                  ),
                  style: TextStyle(
                    fontSize: subtitleFontSize,
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
    _hideControlOverlay();
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

  void _togglePlaybackSettings(BuildContext context) {
    _controlOverlayNotifier.value =
        _controlOverlayNotifier.value == _PlayerControlOverlay.settings
        ? _PlayerControlOverlay.none
        : _PlayerControlOverlay.settings;
  }

  void _showSubtitleOffsetOverlay() {
    _controlOverlayNotifier.value = _PlayerControlOverlay.subtitleOffset;
  }

  void _hideControlOverlay() {
    _controlOverlayNotifier.value = _PlayerControlOverlay.none;
  }

  void _handleSyncPlayStateChange(SyncPlayState? previous, SyncPlayState next) {
    final queue = next.queueEvent;
    if (queue != null && queue.serial != _lastSyncQueueSerial) {
      _lastSyncQueueSerial = queue.serial;
      unawaited(_applySyncPlayQueue(queue));
    }

    final command = next.commandEvent;
    if (command != null && command.serial != _lastSyncCommandSerial) {
      _lastSyncCommandSerial = command.serial;
      unawaited(_applySyncPlayCommand(command.command));
    }
  }

  Future<void> _applySyncPlayQueue(SyncPlayVideoQueueEvent event) async {
    if (!mounted) return;
    if (event.itemId != widget.itemId) {
      final uri = Uri(
        path: '/play/${event.itemId}',
        queryParameters: {
          'resumeTicks': '${event.position.inMilliseconds * _ticksPerMs}',
          'syncPlayPlaying': event.isPlaying ? '1' : '0',
        },
      );
      context.go(uri.toString());
      return;
    }
    _applyingSyncPlayCommand = true;
    try {
      await _player.seek(event.position);
      if (event.isPlaying) {
        await _player.play();
      } else {
        await _player.pause();
      }
      await ref
          .read(syncPlayControllerProvider.notifier)
          .ready(position: event.position, isPlaying: event.isPlaying);
    } finally {
      _applyingSyncPlayCommand = false;
    }
  }

  Future<void> _applySyncPlayCommand(SyncPlayCommand command) async {
    if (!mounted || _isDuplicateSyncPlayCommand(command)) return;
    final targetPlaylistItemId = ref
        .read(syncPlayControllerProvider)
        .currentPlaylistItemId;
    final commandPlaylistItemId = command.playlistItemId;
    final itemIsWildcard =
        commandPlaylistItemId == null ||
        commandPlaylistItemId.isEmpty ||
        commandPlaylistItemId == '00000000000000000000000000000000';
    if (command.command != 'Stop' &&
        !itemIsWildcard &&
        commandPlaylistItemId != targetPlaylistItemId) {
      return;
    }

    final delay = _syncPlayDelayUntil(command.when);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted) return;

    _applyingSyncPlayCommand = true;
    try {
      final targetPosition = _adjustedSyncPlayPosition(command);
      switch (command.command) {
        case 'Unpause':
          if (targetPosition != null) await _player.seek(targetPosition);
          await _player.play();
          break;
        case 'Pause':
          if (targetPosition != null) await _player.seek(targetPosition);
          await _player.pause();
          break;
        case 'Seek':
          if (targetPosition != null) await _player.seek(targetPosition);
          await ref
              .read(syncPlayControllerProvider.notifier)
              .ready(
                position: targetPosition ?? _lastPosition,
                isPlaying: _player.state.playing,
              );
          break;
        case 'Stop':
          await _player.pause();
          break;
      }
    } finally {
      _applyingSyncPlayCommand = false;
    }
  }

  bool _isDuplicateSyncPlayCommand(SyncPlayCommand command) {
    final key = [
      command.command,
      command.playlistItemId ?? '',
      command.position?.inMilliseconds ?? '',
      command.when?.toIso8601String() ?? '',
    ].join('|');
    final now = DateTime.now();
    final lastAt = _lastSyncCommandAt;
    final duplicate =
        _lastSyncCommandKey == key &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 2);
    _lastSyncCommandKey = key;
    _lastSyncCommandAt = now;
    return duplicate;
  }

  Duration _syncPlayDelayUntil(DateTime? when) {
    if (when == null) return Duration.zero;
    final delay = when.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) return Duration.zero;
    return delay > const Duration(seconds: 20)
        ? const Duration(seconds: 20)
        : delay;
  }

  Duration? _adjustedSyncPlayPosition(SyncPlayCommand command) {
    final position = command.position;
    if (position == null) return null;
    if (command.command != 'Unpause' || command.when == null) return position;
    final elapsed = DateTime.now().toUtc().difference(command.when!);
    if (elapsed <= Duration.zero) return position;
    return position + elapsed;
  }

  void _showCastSheet(BuildContext context) {
    _hideControlOverlay();
    showRemoteSessionsSheet(
      context,
      itemId: widget.itemId,
      startPositionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
      onCastStarted: (_) async {
        if (_player.state.playing) {
          await _player.pause();
        }
      },
    );
  }

  void _showSyncPlaySheet(BuildContext context) {
    _hideControlOverlay();
    showSyncPlaySheet(
      context,
      itemId: widget.itemId,
      startPosition: _lastPosition,
      isPlaying: _player.state.playing,
    );
  }
}

class _PlaybackSettingsOverlay extends ConsumerStatefulWidget {
  const _PlaybackSettingsOverlay({
    required this.initialRate,
    required this.initialSubtitleOffset,
    required this.onRateChanged,
    required this.onQualityChanged,
    required this.onOpenSubtitleOffset,
  });

  final double initialRate;
  final Duration initialSubtitleOffset;
  final Future<void> Function(double rate) onRateChanged;
  final Future<void> Function() onQualityChanged;
  final VoidCallback onOpenSubtitleOffset;

  @override
  ConsumerState<_PlaybackSettingsOverlay> createState() =>
      _PlaybackSettingsOverlayState();
}

class _PlaybackSettingsOverlayState
    extends ConsumerState<_PlaybackSettingsOverlay> {
  static const _speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  late double _rate = widget.initialRate;
  bool _qualityBusy = false;

  @override
  Widget build(BuildContext context) {
    final currentQuality = ref
        .watch(playbackPreferencesProvider)
        .streamingQuality;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              letterSpacing: 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Speed')),
                    _CompactDropdown<double>(
                      value: _rate,
                      items: _speedOptions,
                      itemLabel: _speedLabel,
                      onChanged: (value) {
                        if (value != null) _setRate(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('Quality')),
                    if (_qualityBusy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      _CompactDropdown<StreamingQuality>(
                        value: currentQuality,
                        items: StreamingQuality.values,
                        itemLabel: (quality) => quality.label,
                        onChanged: (value) {
                          if (value != null) _setQuality(value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: widget.onOpenSubtitleOffset,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Subtitle offset')),
                        Text(
                          _offsetLabel(widget.initialSubtitleOffset),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setRate(double value) async {
    setState(() => _rate = value);
    await widget.onRateChanged(value);
  }

  Future<void> _setQuality(StreamingQuality value) async {
    final current = ref.read(playbackPreferencesProvider).streamingQuality;
    if (value == current) return;
    setState(() => _qualityBusy = true);
    await ref
        .read(playbackPreferencesProvider.notifier)
        .setStreamingQuality(value);
    await widget.onQualityChanged();
    if (mounted) setState(() => _qualityBusy = false);
  }

  String _speedLabel(double value) {
    return value == 1.0 ? 'Normal' : '${value.toStringAsFixed(2)}x';
  }

  String _offsetLabel(Duration offset) {
    final seconds = offset.inMilliseconds / 1000.0;
    if (seconds == 0) return '0.00s';
    final sign = seconds > 0 ? '+' : '';
    return '$sign${seconds.toStringAsFixed(2)}s';
  }
}

class _SubtitleOffsetOverlay extends StatefulWidget {
  const _SubtitleOffsetOverlay({
    required this.initialSubtitleOffset,
    required this.onSubtitleOffsetChanged,
  });

  final Duration initialSubtitleOffset;
  final Future<void> Function(Duration offset) onSubtitleOffsetChanged;

  @override
  State<_SubtitleOffsetOverlay> createState() => _SubtitleOffsetOverlayState();
}

class _SubtitleOffsetOverlayState extends State<_SubtitleOffsetOverlay> {
  static const _minOffsetSeconds = -30.0;
  static const _maxOffsetSeconds = 30.0;
  static const _zeroMarkerWidth = 2.0;
  static const _zeroMarkerHeight = 16.0;

  late Duration _subtitleOffset = widget.initialSubtitleOffset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  _offsetLabel(_subtitleOffset),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        _setOffsetFromDx(details.localPosition.dx, constraints);
                      },
                      onHorizontalDragUpdate: (details) {
                        _setOffsetFromDx(details.localPosition.dx, constraints);
                      },
                      onTapDown: (details) {
                        _setOffsetFromDx(details.localPosition.dx, constraints);
                      },
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white.withValues(
                            alpha: 0.24,
                          ),
                          thumbColor: AppColors.primary,
                          overlayColor: AppColors.primary.withValues(
                            alpha: 0.16,
                          ),
                          valueIndicatorColor: AppColors.surfaceElevated,
                          valueIndicatorTextStyle: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            IgnorePointer(
                              child: SizedBox(
                                width: _zeroMarkerWidth,
                                height: _zeroMarkerHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                            Slider(
                              min: _minOffsetSeconds,
                              max: _maxOffsetSeconds,
                              divisions: 240,
                              label: _offsetLabel(_subtitleOffset),
                              value: _subtitleOffset.inMilliseconds / 1000.0,
                              onChanged: _setOffsetSeconds,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: 'Reset',
                visualDensity: VisualDensity.compact,
                color: AppColors.textSecondary,
                onPressed: () => _setOffset(Duration.zero),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setOffsetSeconds(double value) {
    final offset = Duration(milliseconds: (value * 1000).round());
    _setOffset(offset);
  }

  void _setOffsetFromDx(double dx, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (width <= 0) return;
    final t = (dx / width).clamp(0.0, 1.0);
    final seconds =
        _minOffsetSeconds + ((_maxOffsetSeconds - _minOffsetSeconds) * t);
    _setOffsetSeconds(seconds);
  }

  Future<void> _setOffset(Duration value) async {
    setState(() => _subtitleOffset = value);
    await widget.onSubtitleOffsetChanged(value);
  }

  String _offsetLabel(Duration offset) {
    final seconds = offset.inMilliseconds / 1000.0;
    if (seconds == 0) return '0.00s';
    final sign = seconds > 0 ? '+' : '';
    return '$sign${seconds.toStringAsFixed(2)}s';
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        dropdownColor: Colors.black.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(8),
        icon: const SizedBox.shrink(),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        selectedItemBuilder: (context) => [
          for (final item in items)
            Align(
              alignment: Alignment.centerRight,
              child: Text(itemLabel(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: onChanged,
        isDense: true,
        alignment: AlignmentDirectional.centerEnd,
        menuMaxHeight: 260,
        menuWidth: 148,
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
