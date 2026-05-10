import 'dart:async';

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
  Future<void> Function(String sessionId)? onCastStarted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RemoteSessionsSheet(
      itemId: itemId,
      startPositionTicks: startPositionTicks,
      onCastStarted: onCastStarted,
    ),
  );
}

class _RemoteSessionsSheet extends ConsumerWidget {
  const _RemoteSessionsSheet({
    this.itemId,
    this.startPositionTicks,
    this.onCastStarted,
  });

  final String? itemId;
  final int? startPositionTicks;
  final Future<void> Function(String sessionId)? onCastStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(remoteSessionsProvider);
    final activeRemoteId = ref.watch(activeRemoteSessionIdProvider);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  const _SheetIcon(icon: Icons.cast_connected_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemId == null ? 'Cast controls' : 'Play on',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Nearby Jellyfin sessions',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (activeRemoteId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _ReturnToDeviceTile(
                  onTap: () => _switchToLocal(context, ref, activeRemoteId),
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _SessionRow(
                      session: sessions[i],
                      itemId: itemId,
                      startPositionTicks: startPositionTicks,
                      onCastStarted: onCastStarted,
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

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 21),
      ),
    );
  }
}

class _ReturnToDeviceTile extends StatelessWidget {
  const _ReturnToDeviceTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.phone_iphone_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This device',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _switchToLocal(
  BuildContext context,
  WidgetRef ref,
  String activeRemoteId,
) async {
  final navigator = Navigator.of(context);
  final repo = ref.read(remoteSessionsRepositoryProvider);
  try {
    await repo.stop(activeRemoteId);
  } catch (_) {
    // The remote may already be gone; clearing local state is what matters.
  }
  ref.read(activeRemoteSessionIdProvider.notifier).clear();
  if (navigator.mounted) navigator.pop();
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.itemId,
    required this.startPositionTicks,
    required this.onCastStarted,
  });

  final RemoteSession session;
  final String? itemId;
  final int? startPositionTicks;
  final Future<void> Function(String sessionId)? onCastStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCast = itemId != null;
    final isActive = ref.watch(activeRemoteSessionIdProvider) == session.id;
    final isControlOnly = !canCast;
    final isIdleControlOnly = isControlOnly && !session.isPlayingSomething;
    final clientLabel = session.client.trim();
    final statusLabel = isIdleControlOnly
        ? 'Open a video to cast here'
        : (clientLabel.isEmpty ? null : clientLabel);

    return Material(
      color: isActive
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canCast ? () => _cast(context, ref) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _DeviceAvatar(icon: _iconForClient(session.client)),
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (statusLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isIdleControlOnly
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isActive)
                    const Icon(Icons.check_rounded, color: AppColors.primary)
                  else if (canCast)
                    const Icon(
                      Icons.cast_rounded,
                      color: AppColors.textTertiary,
                    )
                  else if (session.isPlayingSomething)
                    const Icon(
                      Icons.tune_rounded,
                      color: AppColors.textTertiary,
                    ),
                ],
              ),
              if (session.isPlayingSomething) ...[
                const SizedBox(height: 12),
                _NowPlayingControls(session: session),
              ],
            ],
          ),
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
      ref.read(activeRemoteSessionIdProvider.notifier).set(session.id);
      await onCastStarted?.call(session.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Playing on ${session.deviceName}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Stop',
            onPressed: () async {
              await repo.stop(session.id);
              ref.read(activeRemoteSessionIdProvider.notifier).clear();
            },
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

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
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
  double? _volumeOverride;
  Timer? _volumeDebounce;

  @override
  void dispose() {
    _volumeDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(remoteSessionsRepositoryProvider);
    final session = widget.session;
    final isActive = ref.watch(activeRemoteSessionIdProvider) == session.id;
    final totalTicks = session.runTimeTicks ?? 0;
    final liveMicroseconds = session.estimatedPosition()?.inMicroseconds ?? 0;
    final hasDuration = totalTicks > 0;
    final value =
        _scrubOverride ??
        (hasDuration ? (liveMicroseconds * 10) / totalTicks : 0.0);
    final volumeValue =
        _volumeOverride ?? session.volumeLevel?.clamp(0, 100).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
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
                visualDensity: VisualDensity.compact,
                onPressed: () => repo.playPause(session.id),
              ),
              IconButton(
                icon: const Icon(
                  Icons.stop_rounded,
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Stop',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await repo.stop(session.id);
                  if (isActive) {
                    ref.read(activeRemoteSessionIdProvider.notifier).clear();
                  }
                },
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
                  visualDensity: VisualDensity.compact,
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
                      value: volumeValue ?? 0,
                      onChanged: (v) => _setVolumePreview(repo, session.id, v),
                      onChangeEnd: (v) => _commitVolume(repo, session.id, v),
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

  void _setVolumePreview(
    RemoteSessionsRepository repo,
    String sessionId,
    double value,
  ) {
    setState(() => _volumeOverride = value);
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 120), () {
      repo.setVolume(sessionId, value.round());
    });
  }

  Future<void> _commitVolume(
    RemoteSessionsRepository repo,
    String sessionId,
    double value,
  ) async {
    _volumeDebounce?.cancel();
    await repo.setVolume(sessionId, value.round());
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _volumeOverride = null);
  }
}
