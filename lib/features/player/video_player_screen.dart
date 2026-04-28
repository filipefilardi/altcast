import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_colors.dart';
import '../../data/jellyfin/jellyfin_repository.dart';

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
  Object? _openError;

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

    _open();
  }

  Future<void> _open() async {
    try {
      final url = ref.read(jellyfinRepositoryProvider).streamUrl(widget.itemId);
      await _player.open(Media(url));
      final ticks = widget.resumeTicks ?? 0;
      if (ticks > 0) {
        await _player.seek(Duration(microseconds: ticks ~/ 10));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _openError = e);
    }
  }

  @override
  void dispose() {
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
