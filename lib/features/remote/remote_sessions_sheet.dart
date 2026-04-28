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
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
                Icon(
                  _iconForClient(session.client),
                  color: AppColors.primary,
                ),
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
            onPressed: () => repo.sendCommand(
              sessionId: session.id,
              command: 'Stop',
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Cast failed: $e')),
      );
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

class _NowPlayingControls extends ConsumerWidget {
  const _NowPlayingControls({required this.session});
  final RemoteSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(remoteSessionsRepositoryProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.nowPlayingTitle ?? 'Now playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (session.runTimeTicks != null &&
                    session.positionTicks != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatProgress(session),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
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
            onPressed: () => repo.sendCommand(
              sessionId: session.id,
              command: 'PlayPause',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_rounded, color: AppColors.textSecondary),
            tooltip: 'Stop',
            onPressed: () => repo.sendCommand(
              sessionId: session.id,
              command: 'Stop',
            ),
          ),
        ],
      ),
    );
  }

  String _formatProgress(RemoteSession s) {
    final pos = Duration(microseconds: (s.positionTicks ?? 0) ~/ 10);
    final total = Duration(microseconds: (s.runTimeTicks ?? 0) ~/ 10);
    return '${formatDuration(pos)} / ${formatDuration(total)}';
  }
}
