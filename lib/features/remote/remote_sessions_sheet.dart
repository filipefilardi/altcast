import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../data/jellyfin/models/remote_session.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';
import 'remote_providers.dart';

/// Opens the cast picker / mini-control sheet.
///
/// [itemId] is what we ask the chosen device to play. Pass `null` to use
/// this purely as a control sheet for already-playing remote sessions
/// (e.g. when entered from a global "Cast" entry).
Future<void> showRemoteSessionsSheet(
  BuildContext context, {
  String? itemId,
  int? startPositionTicks,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RemoteSessionsSheet(
      itemId: itemId,
      startPositionTicks: startPositionTicks,
    ),
  );
}

class _RemoteSessionsSheet extends ConsumerWidget {
  const _RemoteSessionsSheet({this.itemId, this.startPositionTicks});

  final String? itemId;
  final int? startPositionTicks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(remoteSessionsProvider);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.cast, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text(
                    'Play on…',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: sessionsAsync.when(
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: EmptyState(
                        icon: Icons.cast_outlined,
                        title: 'No devices found',
                        message:
                            'Open Jellyfin on another device to see it here.',
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _SessionRow(
                      session: sessions[i],
                      itemId: itemId,
                      startPositionTicks: startPositionTicks,
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ErrorStateView(
                    title: "Couldn't reach server",
                    message: e.toString(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.itemId,
    required this.startPositionTicks,
  });

  final RemoteSession session;
  final String? itemId;
  final int? startPositionTicks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCast = itemId != null;
    return InkWell(
      onTap: canCast ? () => _cast(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForClient(session.client), color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (session.client.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          session.client,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canCast)
                  const Icon(Icons.cast, color: AppColors.textTertiary),
              ],
            ),
            if (session.isPlayingSomething) ...[
              const SizedBox(height: 12),
              _NowPlayingControls(session: session),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cast(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(remoteSessionsRepositoryProvider);
    try {
      await repo.playOnSession(
        sessionId: session.id,
        itemId: itemId!,
        startPositionTicks: startPositionTicks ?? 0,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Playing on ${session.deviceName}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Stop',
            onPressed: () =>
                repo.sendCommand(sessionId: session.id, command: 'Stop'),
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Cast failed: $e')));
    }
  }

  IconData _iconForClient(String client) {
    final c = client.toLowerCase();
    if (c.contains('android') || c.contains('iphone') || c.contains('ios')) {
      return Icons.phone_iphone;
    }
    if (c.contains('tv') ||
        c.contains('roku') ||
        c.contains('shield') ||
        c.contains('chromecast')) {
      return Icons.tv;
    }
    if (c.contains('web') || c.contains('chrome') || c.contains('safari')) {
      return Icons.public;
    }
    return Icons.devices;
  }
}

/// Inline mini-control rendered under a session row when that session is
/// playing something. Title + scrubber + transport controls.
///
/// The scrubber is the tricky bit: the parent rebuilds every 3 s with fresh
/// [RemoteSession] data, which would yank the slider out from under the
/// user's finger. We mirror the polled position into local state and freeze
/// it while the user is dragging — only the next poll AFTER drag release
/// is allowed to take over again.
class _NowPlayingControls extends ConsumerStatefulWidget {
  const _NowPlayingControls({required this.session});
  final RemoteSession session;

  @override
  ConsumerState<_NowPlayingControls> createState() =>
      _NowPlayingControlsState();
}

class _NowPlayingControlsState extends ConsumerState<_NowPlayingControls> {
  /// Position the slider should render. `null` → mirror the polled value.
  double? _scrubOverride;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(remoteSessionsRepositoryProvider);
    final session = widget.session;
    final totalTicks = session.runTimeTicks ?? 0;
    final liveMicroseconds = session.estimatedPosition()?.inMicroseconds ?? 0;
    final hasDuration = totalTicks > 0;
    final value =
        _scrubOverride ??
        (hasDuration ? (liveMicroseconds * 10) / totalTicks : 0.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.nowPlayingTitle ?? 'Now playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  session.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: AppColors.primary,
                ),
                tooltip: session.isPaused ? 'Play' : 'Pause',
                onPressed: () => repo.playPause(session.id),
              ),
              IconButton(
                icon: const Icon(
                  Icons.stop_rounded,
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Stop',
                onPressed: () => repo.stop(session.id),
              ),
            ],
          ),
          if (session.volumeLevel != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    session.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: session.isMuted ? 'Unmute' : 'Mute',
                  onPressed: () =>
                      repo.setMute(session.id, muted: !session.isMuted),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: session.volumeLevel!.clamp(0, 100).toDouble(),
                      onChanged: (v) => repo.setVolume(session.id, v.round()),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (hasDuration) ...[
            // Scrub bar — Slider.theme honors AppTheme so it picks up the
            // accent + height we set globally. Using the raw widget so we
            // can intercept onChanged/onChangeEnd.
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(0, 1),
                onChanged: (v) => setState(() => _scrubOverride = v),
                onChangeEnd: (v) async {
                  final targetTicks = (v * totalTicks).round();
                  await repo.seekOnSession(
                    sessionId: session.id,
                    positionTicks: targetTicks,
                  );
                  // Keep the override around briefly so the slider doesn't
                  // jump back to the (now-stale) polled position before the
                  // next poll lands.
                  await Future<void>.delayed(const Duration(seconds: 4));
                  if (mounted) setState(() => _scrubOverride = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(
                      Duration(
                        microseconds: ((value * totalTicks).round()) ~/ 10,
                      ),
                    ),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    formatDuration(Duration(microseconds: totalTicks ~/ 10)),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
