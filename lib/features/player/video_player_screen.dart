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

  Future<void> _open() async {
    try {
      final url = ref.read(jellyfinRepositoryProvider).streamUrl(widget.itemId);
      await _player.open(Media(url));
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
    final scrobbler = _Scrobbler(api: api, itemId: widget.itemId);
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => context.pop(),
                ),
              ),
            ),
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
  _Scrobbler({required this.api, required this.itemId});

  final JellyfinApi api;
  final String itemId;

  Future<void> start({required int positionTicks}) {
    return _post('/Sessions/Playing', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      'IsPaused': false,
      'PlayMethod': 'DirectStream',
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
    });
  }

  Future<void> stop({required int positionTicks}) {
    return _post('/Sessions/Playing/Stopped', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
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
