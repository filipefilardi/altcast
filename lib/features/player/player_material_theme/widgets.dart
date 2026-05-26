part of '../player_material_theme.dart';

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
