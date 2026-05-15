import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/features/syncplay/syncplay_controller.dart';

Future<void> showSyncPlaySheet(
  BuildContext context, {
  String? itemId,
  Duration startPosition = Duration.zero,
  bool isPlaying = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SyncPlaySheet(
      itemId: itemId,
      startPosition: startPosition,
      isPlaying: isPlaying,
    ),
  );
}

class _SyncPlaySheet extends ConsumerStatefulWidget {
  const _SyncPlaySheet({
    required this.itemId,
    required this.startPosition,
    required this.isPlaying,
  });

  final String? itemId;
  final Duration startPosition;
  final bool isPlaying;

  @override
  ConsumerState<_SyncPlaySheet> createState() => _SyncPlaySheetState();
}

class _SyncPlaySheetState extends ConsumerState<_SyncPlaySheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncPlayControllerProvider.notifier).refreshGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncPlayControllerProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.activeGroup != null)
              _buildActiveGroup(context, state, controller)
            else
              _buildJoinGroup(context, state, controller),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJoinGroup(
    BuildContext context,
    SyncPlayState state,
    SyncPlayController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Join SyncPlay', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (state.loading && state.groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final group in state.groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_rounded),
              title: Text(group.name),
              subtitle: Text(
                group.participants.isEmpty
                    ? 'No users connected'
                    : group.participants.join(', '),
              ),
              onTap: state.loading
                  ? null
                  : () async {
                      await controller.joinGroup(group.id);
                      if (context.mounted &&
                          ref.read(syncPlayControllerProvider).activeGroup !=
                              null) {
                        Navigator.of(context).pop();
                      }
                    },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_rounded),
            title: const Text('New group'),
            subtitle: const Text('Start a room with this video'),
            onTap: state.loading
                ? null
                : () async {
                    await controller.createGroup(
                      name: '',
                      itemId: widget.itemId,
                      startPosition: widget.startPosition,
                      publishCurrentVideo: widget.itemId != null,
                    );
                    if (!widget.isPlaying &&
                        ref.read(syncPlayControllerProvider).activeGroup !=
                            null) {
                      await controller.pause();
                    }
                    if (context.mounted &&
                        ref.read(syncPlayControllerProvider).activeGroup !=
                            null) {
                      Navigator.of(context).pop();
                    }
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildActiveGroup(
    BuildContext context,
    SyncPlayState state,
    SyncPlayController controller,
  ) {
    final group = state.activeGroup!;
    final participants = group.participants.isEmpty
        ? 'No users connected'
        : group.participants.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(group.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          participants,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        if (widget.itemId != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Sync current video'),
            subtitle: const Text('Make this video the room playback'),
            onTap: () async {
              Navigator.of(context).pop();
              await controller.setCurrentVideo(
                widget.itemId!,
                startPosition: widget.startPosition,
              );
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Leave group'),
          subtitle: const Text('Disable SyncPlay'),
          onTap: () async {
            Navigator.of(context).pop();
            await controller.leaveGroup();
          },
        ),
      ],
    );
  }
}
