import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_colors.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_api.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/stream_source.dart';

/// Jellyfin's PositionTicks unit: 1 ms = 10000 ticks (100-ns ticks).
const _ticksPerMs = 10000;

/// Full-screen video player. Routes here are entered via
/// `/play/:id?resumeTicks=N` — the optional `resumeTicks` (Jellyfin tick
/// count, 100 ns) is applied with [Player.seek] right after open.
///
/// We intentionally lean on [MaterialVideoControls] for the on-screen UI
/// (scrubber, play/pause, skip ±10 s, volume, fullscreen). Customising it
/// is a follow-up — the goal here is "video plays, can be scrubbed".
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.itemId,
    this.resumeTicks,
  });

  final String itemId;

  /// Jellyfin tick count (100 ns units) — converts to a [Duration] via
  /// `microseconds = ticks ~/ 10`.
  final int? resumeTicks;

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

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    // Lock to landscape while the player is on screen. Best-effort:
    // ignore platforms (web, desktop) that don't support orientation locks.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _positionSub = _player.stream.position.listen((p) => _lastPosition = p);

    _open();
  }

  StreamSource? _source;

  Future<void> _open() async {
    try {
      final source = await ref
          .read(jellyfinRepositoryProvider)
          .getStreamSource(widget.itemId);
      _source = source;
      await _player.open(Media(source.url));
      final ticks = widget.resumeTicks ?? 0;
      if (ticks > 0) {
        final at = Duration(microseconds: ticks ~/ 10);
        await _player.seek(at);
        _lastPosition = at;
      }
      _attachScrobbler();
    } catch (e) {
      if (!mounted) return;
      setState(() => _openError = e);
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
    });

    // When the file finishes, fire a final stop with full position so
    // Jellyfin marks it played.
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        scrobbler.stop(
          positionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
        );
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    // Best-effort final stop so the server records where the user left off.
    _scrobbler?.stop(
      positionTicks: _lastPosition.inMilliseconds * _ticksPerMs,
    );
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_openError != null)
              _PlaybackError(
                error: _openError!,
                onClose: () => context.pop(),
              )
            else
              Video(
                controller: _controller,
                controls: AdaptiveVideoControls,
                fit: BoxFit.contain,
              ),
            // Always-visible close button — the built-in controls auto-hide,
            // and a video that's failed to open has no controls at all, so
            // we keep this anchored.
            Positioned(
              top: 8,
              left: 8,
              child: _CornerButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => context.pop(),
              ),
            ),
            if (_openError == null)
              Positioned(
                top: 8,
                right: 8,
                child: _CornerButton(
                  icon: Icons.subtitles_outlined,
                  tooltip: 'Audio & Subtitles',
                  onPressed: () => _showTracksSheet(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TracksSheet(player: _player),
    );
  }
}

/// Round translucent button used for the always-visible top-corner overlays.
class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onPressed,
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
  const _TracksSheet({required this.player});
  final Player player;

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
              final tracks = tracksSnap.data ?? player.state.tracks;
              final current = currentSnap.data ?? player.state.track;
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
                      ),
                    ],
                  ),
                ),
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
        .where((t) => t.id != AudioTrack.auto().id && t.id != AudioTrack.no().id)
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

  String _audioLabel(AudioTrack t) {
    final pieces = <String>[
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    if (pieces.isEmpty) return 'Track ${t.id}';
    return pieces.join(' · ');
  }
}

class _SubtitleSection extends StatelessWidget {
  const _SubtitleSection({
    required this.player,
    required this.tracks,
    required this.current,
  });

  final Player player;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack current;

  @override
  Widget build(BuildContext context) {
    final real = tracks
        .where((t) =>
            t.id != SubtitleTrack.auto().id && t.id != SubtitleTrack.no().id)
        .toList();
    final isOff = current.id == SubtitleTrack.no().id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Subtitles'),
        _TrackRow(
          label: 'Off',
          selected: isOff,
          onTap: () {
            player.setSubtitleTrack(SubtitleTrack.no());
            Navigator.of(context).pop();
          },
        ),
        if (real.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'No subtitle tracks available.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          )
        else
          for (final t in real)
            _TrackRow(
              label: _subtitleLabel(t),
              selected: !isOff && t.id == current.id,
              onTap: () {
                player.setSubtitleTrack(t);
                Navigator.of(context).pop();
              },
            ),
      ],
    );
  }

  String _subtitleLabel(SubtitleTrack t) {
    final pieces = <String>[
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    if (pieces.isEmpty) return 'Track ${t.id}';
    return pieces.join(' · ');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
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
            const Icon(Icons.error_outline,
                color: AppColors.error, size: 40),
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
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onClose,
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
