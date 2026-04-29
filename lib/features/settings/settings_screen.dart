import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../../features/auth/auth_controller.dart';

final _serverInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  try {
    final res = await ref
        .watch(jellyfinApiProvider)
        .dio
        .get<Map<String, dynamic>>('/System/Info/Public');
    return res.data;
  } catch (_) {
    return null;
  }
});

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = auth is AuthAuthenticated ? auth.session : null;
    final downloads = ref.watch(downloadManagerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          if (session != null) ...[
            _AccountCard(
              username: session.username,
              serverUrl: session.serverUrl,
            ),
            const SizedBox(height: 28),
          ],
          _SettingsGroup(
            label: 'Library',
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Downloads'),
                subtitle: Text(
                  _downloadsSubtitle(downloads),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
                onTap: () => context.push('/downloads'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SignOutTile(),
          const SizedBox(height: 28),
          const _VersionFooter(),
        ],
      ),
    );
  }

  String _downloadsSubtitle(DownloadsState s) {
    if (!s.bootstrapped) return 'Loading...';
    final pending = s.progress.length;
    final done = s.items.length;
    if (done == 0 && pending == 0) return 'Nothing offline yet';
    final parts = <String>[
      if (done > 0) '$done available offline',
      if (pending > 0) '$pending downloading',
    ];
    return parts.join(' • ');
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.username, required this.serverUrl});

  final String username;
  final String serverUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_serverInfoProvider);
    final bool? online = info.when(
      data: (i) => i != null,
      loading: () => null,
      error: (_, _) => false,
    );

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAccountSheet(context, username, serverUrl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Avatar(name: username),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusDot(online: online),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            serverUrl,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showAccountSheet(
  BuildContext context,
  String username,
  String serverUrl,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final info = ref.watch(_serverInfoProvider);
        String infoValue(String key) {
          return info.when(
            data: (i) => i == null ? 'Unreachable' : (i[key] as String? ?? '-'),
            loading: () => 'Checking...',
            error: (_, _) => 'Unreachable',
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'User', value: username),
                _DetailRow(label: 'Server', value: serverUrl),
                _DetailRow(
                  label: 'Server name',
                  value: infoValue('ServerName'),
                ),
                _DetailRow(
                  label: 'Server version',
                  value: infoValue('Version'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initials = trimmed.isEmpty
        ? '?'
        : trimmed
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        gradient: AppGradients.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online});

  final bool? online;

  @override
  Widget build(BuildContext context) {
    final color = online == null
        ? AppColors.textTertiary
        : online!
        ? const Color(0xFF66CC8A)
        : AppColors.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutTile extends ConsumerWidget {
  const _SignOutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.logout, color: AppColors.error),
        title: const Text('Sign out', style: TextStyle(color: AppColors.error)),
        onTap: () async {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.pop();
        },
      ),
    );
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkg = ref.watch(_packageInfoProvider);
    return Center(
      child: Text(
        pkg.when(
          data: (p) => 'AltCast ${p.version}',
          loading: () => 'AltCast',
          error: (_, _) => 'AltCast',
        ),
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(const Divider(height: 1, indent: 56));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Material(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

