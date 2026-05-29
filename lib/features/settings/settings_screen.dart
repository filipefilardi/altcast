import 'dart:io';

import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/utils/language.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/local/download_preferences.dart';
import 'package:altcast/data/local/playback_preferences.dart';
import 'package:altcast/features/auth/auth_controller.dart';

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
          const _DownloadGroup(),
          const SizedBox(height: 24),
          const _PlaybackGroup(),
          const SizedBox(height: 24),
          const _AudioSubtitleGroup(),
          const SizedBox(height: 28),
          const _SignOutTile(),
          const SizedBox(height: 28),
          const _VersionFooter(),
        ],
      ),
    );
  }

  static String _downloadsSubtitle(DownloadsState s) {
    if (!s.bootstrapped) return 'Loading...';
    final pending = s.progress.length;
    final failed = s.failures.length;
    final done = s.items.length;
    if (done == 0 && pending == 0 && failed == 0) return 'Nothing offline yet';
    final parts = <String>[
      if (done > 0) '$done available offline',
      if (pending > 0) '$pending downloading',
      if (failed > 0) '$failed failed',
    ];
    return parts.join(' • ');
  }
}

class _DownloadGroup extends ConsumerWidget {
  const _DownloadGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(downloadPreferencesProvider);
    final notifier = ref.read(downloadPreferencesProvider.notifier);
    final downloads = ref.watch(downloadManagerProvider);
    final hasDownloads =
        downloads.items.isNotEmpty ||
        downloads.progress.isNotEmpty ||
        downloads.failures.isNotEmpty;

    return _SettingsGroup(
      label: 'Library',
      children: [
        ListTile(
          leading: const Icon(PiconsRegular.downloadSimple),
          title: const Text('Downloads'),
          subtitle: Text(
            SettingsScreen._downloadsSubtitle(downloads),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretRight,
            color: AppColors.textSecondary,
          ),
          onTap: () => context.push('/downloads'),
        ),
        SwitchListTile(
          secondary: const Icon(PiconsRegular.wifiHigh),
          title: const Text('Wi-Fi only downloads'),
          subtitle: const Text('Avoid downloading videos on mobile data.'),
          value: prefs.wifiOnlyDownloads,
          onChanged: notifier.setWifiOnlyDownloads,
          activeThumbColor: AppColors.primary,
        ),
        SwitchListTile(
          secondary: const Icon(PiconsRegular.arrowsClockwise),
          title: const Text('Auto-download next'),
          subtitle: const Text('New episodes arrive while you watch'),
          value: prefs.autoDownloadNextEpisode,
          onChanged: notifier.setAutoDownloadNextEpisode,
          activeThumbColor: AppColors.primary,
        ),
        ListTile(
          leading: const Icon(PiconsRegular.highDefinition),
          title: const Text('Offline video quality'),
          subtitle: Text(
            prefs.offlineVideoQuality.label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretDown,
            color: AppColors.textSecondary,
          ),
          onTap: () => _showOfflineQualityPicker(context, ref),
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(PiconsRegular.hardDrives),
            title: const Text('Storage location'),
            subtitle: Text(
              prefs.downloadLocation.label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: const Icon(
              PiconsRegular.caretDown,
              color: AppColors.textSecondary,
            ),
            onTap: () => _showLocationPicker(context, ref),
          ),
        ListTile(
          leading: Icon(
            PiconsRegular.trash,
            color: hasDownloads ? AppColors.textSecondary : AppColors.textTertiary,
          ),
          title: Text(
            'Delete all downloads',
            style: TextStyle(
              color: hasDownloads ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
          subtitle: const Text(
            'Remove all offline videos and queued downloads from this device.',
          ),
          onTap: hasDownloads
              ? () => _confirmDeleteAllDownloads(context, ref)
              : null,
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAllDownloads(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete all downloads?'),
        content: const Text(
          'This removes all offline videos and queued downloads from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(downloadManagerProvider.notifier).deleteAll();
    if (!context.mounted) return;
    showAppSnackBar(context, 'All downloads were deleted.');
  }

  void _showLocationPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: DownloadLocation.values.map((loc) {
            final selected =
                ref.watch(downloadPreferencesProvider).downloadLocation == loc;
            return ListTile(
              leading: Icon(
                loc == DownloadLocation.internal
                    ? PiconsRegular.deviceMobile
                    : PiconsRegular.hardDrives,
                color: selected ? AppColors.primary : null,
              ),
              title: Text(loc.label),
              trailing: selected
                  ? const Icon(PiconsRegular.check, color: AppColors.primary)
                  : null,
              onTap: () {
                ref
                    .read(downloadPreferencesProvider.notifier)
                    .setDownloadLocation(loc);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showOfflineQualityPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: OfflineVideoQuality.values.map((quality) {
            final selected =
                ref.watch(downloadPreferencesProvider).offlineVideoQuality ==
                quality;
            return ListTile(
              leading: Icon(
                PiconsRegular.sparkle,
                color: selected ? AppColors.primary : null,
              ),
              title: Text(quality.label),
              trailing: selected
                  ? const Icon(PiconsRegular.check, color: AppColors.primary)
                  : null,
              onTap: () {
                ref
                    .read(downloadPreferencesProvider.notifier)
                    .setOfflineVideoQuality(quality);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PlaybackGroup extends ConsumerWidget {
  const _PlaybackGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(playbackPreferencesProvider);
    return _SettingsGroup(
      label: 'Playback',
      children: [
        ListTile(
          leading: const Icon(PiconsRegular.highDefinition),
          title: const Text('Streaming quality'),
          subtitle: Text(
            prefs.streamingQuality.label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretRight,
            color: AppColors.textSecondary,
          ),
          onTap: () => _showStreamingQualitySheet(context),
        ),
        SwitchListTile(
          secondary: const Icon(PiconsRegular.playCircle),
          title: const Text('Autoplay next episode'),
          subtitle: const Text(
            'After an episode ends, continue to the next one automatically.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          value: prefs.autoplayNextTvEpisode,
          onChanged: (v) => ref
              .read(playbackPreferencesProvider.notifier)
              .setAutoplayNextTvEpisode(v),
          activeThumbColor: AppColors.primary,
        ),
        if (prefs.autoplayNextTvEpisode)
          ListTile(
            leading: const Icon(PiconsRegular.clock),
            title: const Text('Autoplay countdown'),
            subtitle: Text(
              '${prefs.autoplayCountdownSeconds} seconds',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: const Icon(
              PiconsRegular.caretRight,
              color: AppColors.textSecondary,
            ),
            onTap: () => _showAutoplayCountdownSheet(context),
          ),
        if (Platform.isAndroid)
          SwitchListTile(
            secondary: const Icon(PiconsRegular.cpu),
            title: const Text('Software video decoding'),
            subtitle: const Text(
              'Turn on if some titles show glitchy picture on this device '
              '(uses more CPU and battery).',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            value: prefs.androidSoftwareVideoDecode,
            onChanged: (v) => ref
                .read(playbackPreferencesProvider.notifier)
                .setAndroidSoftwareVideoDecode(v),
            activeThumbColor: AppColors.primary,
          ),
      ],
    );
  }
}

class _AudioSubtitleGroup extends ConsumerWidget {
  const _AudioSubtitleGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(playbackPreferencesProvider);
    return _SettingsGroup(
      label: 'Audio & Subtitles',
      children: [
        ListTile(
          leading: const Icon(PiconsRegular.speakerHigh),
          title: const Text('Default audio'),
          subtitle: Text(
            _audioDefaultLabel(prefs),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretRight,
            color: AppColors.textSecondary,
          ),
          onTap: () => _showDefaultAudioSheet(context),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.closedCaptioning),
          title: const Text('Default subtitles'),
          subtitle: Text(
            _subtitleDefaultLabel(
              prefs.defaultSubtitleMode,
              prefs.defaultSubtitleLanguage,
            ),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretRight,
            color: AppColors.textSecondary,
          ),
          onTap: () => _showDefaultSubtitleSheet(context),
        ),
        ListTile(
          leading: const Icon(PiconsRegular.slidersHorizontal),
          title: const Text('Subtitle appearance'),
          subtitle: Text(
            _subtitleAppearanceSummary(
              scale: prefs.subtitleFontScale,
              inset: prefs.subtitleBottomInset,
            ),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(
            PiconsRegular.caretRight,
            color: AppColors.textSecondary,
          ),
          onTap: () => _showSubtitleAppearanceSheet(context),
        ),
      ],
    );
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
              const Icon(
                PiconsRegular.caretRight,
                color: AppColors.textSecondary,
              ),
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
      decoration: BoxDecoration(
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
        ? AppColors.success
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
        leading: const Icon(PiconsRegular.signOut, color: AppColors.error),
        title: const Text('Sign out', style: TextStyle(color: AppColors.error)),
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('Sign out?'),
              content: const Text(
                'You will need to enter your server URL and credentials again to sign back in.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          // Auth-state change drives the router redirect; no manual pop needed.
          await ref.read(authControllerProvider.notifier).logout();
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

Future<void> _showAutoplayCountdownSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final current = ref
            .watch(playbackPreferencesProvider)
            .autoplayCountdownSeconds;
        return _scrollableSheet(
          context: context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Autoplay countdown',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'How long the Next Up card waits before jumping to the next episode.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final seconds in autoplayCountdownPresets)
                ListTile(
                  title: Text('$seconds seconds'),
                  contentPadding: EdgeInsets.zero,
                  trailing: seconds == current
                      ? const Icon(
                          PiconsRegular.check,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () async {
                    await ref
                        .read(playbackPreferencesProvider.notifier)
                        .setAutoplayCountdownSeconds(seconds);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showStreamingQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playbackPreferencesProvider).streamingQuality;
        return _scrollableSheet(
          context: context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Streaming quality',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              for (final q in StreamingQuality.values)
                ListTile(
                  title: Text(q.label),
                  subtitle: Text(
                    q.subtitle,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  contentPadding: EdgeInsets.zero,
                  trailing: q == current
                      ? const Icon(
                          PiconsRegular.check,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () async {
                    await ref
                        .read(playbackPreferencesProvider.notifier)
                        .setStreamingQuality(q);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showDefaultAudioSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final prefs = ref.watch(playbackPreferencesProvider);
        final audioCodes = _orderedLanguageCodes(
          selected: prefs.defaultAudioLanguage,
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text(
                'Default audio',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Choose original audio per title, or force one language.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              _defaultTrackOption(
                context: context,
                selected:
                    prefs.defaultAudioMode == DefaultAudioMode.originalLanguage,
                label: 'Original audio',
                subtitle: 'Uses each title\'s metadata when available.',
                onTap: () async {
                  await ref
                      .read(playbackPreferencesProvider.notifier)
                      .setDefaultAudioOriginalLanguage();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Choose language',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final code in audioCodes)
                _defaultTrackOption(
                  context: context,
                  selected:
                      prefs.defaultAudioMode ==
                          DefaultAudioMode.fixedLanguage &&
                      prefs.defaultAudioLanguage == code,
                  label: languageDisplay(code) ?? code,
                  onTap: () async {
                    await ref
                        .read(playbackPreferencesProvider.notifier)
                        .setDefaultAudioFixedLanguage(code);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showDefaultSubtitleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final prefs = ref.watch(playbackPreferencesProvider);
        final subtitleCodes = _orderedLanguageCodes(
          selected: prefs.defaultSubtitleLanguage,
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text(
                'Default subtitles',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              _defaultTrackOption(
                context: context,
                selected: prefs.defaultSubtitleMode == DefaultSubtitleMode.off,
                label: 'Off',
                onTap: () async {
                  await ref
                      .read(playbackPreferencesProvider.notifier)
                      .setDefaultSubtitleOff();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 4),
              for (final code in subtitleCodes)
                _defaultTrackOption(
                  context: context,
                  selected:
                      prefs.defaultSubtitleMode ==
                          DefaultSubtitleMode.byLanguage &&
                      prefs.defaultSubtitleLanguage == code,
                  label: languageDisplay(code) ?? code,
                  onTap: () async {
                    await ref
                        .read(playbackPreferencesProvider.notifier)
                        .setDefaultSubtitleLanguage(code);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}

String _audioDefaultLabel(PlaybackPreferences prefs) {
  switch (prefs.defaultAudioMode) {
    case DefaultAudioMode.auto:
      return _languageOrPlaceholder(prefs.defaultAudioLanguage);
    case DefaultAudioMode.originalLanguage:
      return 'Original audio';
    case DefaultAudioMode.fixedLanguage:
      return _languageOrPlaceholder(prefs.defaultAudioLanguage);
  }
}

String _subtitleDefaultLabel(DefaultSubtitleMode mode, String? code) {
  switch (mode) {
    case DefaultSubtitleMode.auto:
      return 'Off';
    case DefaultSubtitleMode.off:
      return 'Off';
    case DefaultSubtitleMode.byLanguage:
      return _languageOrPlaceholder(code);
  }
}

String _languageOrPlaceholder(String? code) {
  if (code == null || code.isEmpty) return 'Select language';
  return languageDisplay(code) ?? code;
}

List<String> _orderedLanguageCodes({String? selected}) {
  final code = selected?.trim().toLowerCase();
  if (code == null || code.isEmpty || !_commonLanguageCodes.contains(code)) {
    return _commonLanguageCodes;
  }
  return [
    code,
    for (final c in _commonLanguageCodes)
      if (c != code) c,
  ];
}

String _subtitleAppearanceSummary({
  required double scale,
  required double inset,
}) {
  final size = scale == 1.0 ? 'Default size' : '${(scale * 100).round()}% size';
  final pos = inset == 0
      ? 'default position'
      : '${inset.round()}px vertical shift';
  return '$size · $pos';
}

Widget _scrollableSheet({
  required BuildContext context,
  required Widget child,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
  return SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: child,
      ),
    ),
  );
}

Future<void> _showSubtitleAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _SubtitleAppearanceSheet(),
  );
}

class _SubtitleAppearanceSheet extends ConsumerStatefulWidget {
  const _SubtitleAppearanceSheet();

  @override
  ConsumerState<_SubtitleAppearanceSheet> createState() =>
      _SubtitleAppearanceSheetState();
}

class _SubtitleAppearanceSheetState
    extends ConsumerState<_SubtitleAppearanceSheet> {
  late double _fontScale;
  late double _bottomInset;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(playbackPreferencesProvider);
    _fontScale = prefs.subtitleFontScale;
    _bottomInset = prefs.subtitleBottomInset;
  }

  @override
  Widget build(BuildContext context) {
    return _scrollableSheet(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subtitle appearance',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          _SubtitlePreviewCard(
            fontScale: _fontScale,
            bottomInset: _bottomInset,
          ),
          const SizedBox(height: 16),
          Text(
            'Size (${(_fontScale * 100).round()}%)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            min: subtitleFontScalePresets.first,
            max: subtitleFontScalePresets.last,
            divisions:
                ((subtitleFontScalePresets.last -
                            subtitleFontScalePresets.first) /
                        0.05)
                    .round(),
            value: _fontScale,
            label: '${(_fontScale * 100).round()}%',
            onChanged: (v) => setState(() => _fontScale = v),
          ),
          const SizedBox(height: 8),
          Text(
            'Vertical position (${_bottomInset.round()} px)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            min: subtitleBottomInsetPresets.first,
            max: subtitleBottomInsetPresets.last,
            divisions:
                (subtitleBottomInsetPresets.last -
                        subtitleBottomInsetPresets.first)
                    .round(),
            value: _bottomInset,
            label: '${_bottomInset.round()} px',
            onChanged: (v) => setState(() => _bottomInset = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _fontScale = 1.0;
                    _bottomInset = 0.0;
                  });
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _openFullscreenPreview(
                  context,
                  fontScale: _fontScale,
                  bottomInset: _bottomInset,
                ),
                child: const Text('Full-screen preview'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final notifier = ref.read(
                    playbackPreferencesProvider.notifier,
                  );
                  await notifier.setSubtitleFontScale(_fontScale);
                  await notifier.setSubtitleBottomInset(_bottomInset);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubtitlePreviewCard extends StatelessWidget {
  const _SubtitlePreviewCard({
    required this.fontScale,
    required this.bottomInset,
  });

  final double fontScale;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final baseFont = 24.0;
    final fontSize = (baseFont * fontScale).clamp(16.0, 56.0);
    final bottomPad = (44.0 + bottomInset).clamp(12.0, 180.0);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2C2C2C), Color(0xFF151515)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x88000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: bottomPad,
              child: Text(
                'The subtitle preview updates live while you adjust.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  backgroundColor: Colors.black26,
                  shadows: const [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openFullscreenPreview(
  BuildContext context, {
  required double fontScale,
  required double bottomInset,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _SubtitleFullscreenPreview(
      fontScale: fontScale,
      bottomInset: bottomInset,
    ),
  );
}

class _SubtitleFullscreenPreview extends StatelessWidget {
  const _SubtitleFullscreenPreview({
    required this.fontScale,
    required this.bottomInset,
  });

  final double fontScale;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortestSide = mq.size.shortestSide;
    final isTabletClass = shortestSide >= 600;
    final baseFont = isTabletClass ? 32.0 : 24.0;
    final fontSize = (baseFont * fontScale).clamp(16.0, 56.0);
    final baseBottom = (isTabletClass ? 96.0 : 44.0) + mq.padding.bottom;
    final bottomPad = (baseBottom + bottomInset).clamp(16.0, 220.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1F1F1F), Color(0xFF090909)],
              ),
            ),
          ),
          Positioned(
            top: mq.padding.top + 12,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(PiconsRegular.x, color: Colors.white),
              tooltip: 'Close preview',
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomPad,
            child: Text(
              'This is how subtitles will appear during playback.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.2,
                backgroundColor: Colors.black26,
                shadows: const [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _defaultTrackOption({
  required BuildContext context,
  required bool selected,
  required String label,
  required Future<void> Function() onTap,
  String? subtitle,
}) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
    trailing: selected
        ? const Icon(PiconsRegular.check, color: AppColors.primary, size: 18)
        : null,
    onTap: () {
      onTap();
    },
  );
}

const _commonLanguageCodes = <String>[
  'en',
  'pt',
  'es',
  'fr',
  'de',
  'it',
  'ja',
  'ko',
  'zh',
  'ru',
];

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
