import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/language.dart';
import '../../../data/jellyfin/models/stream_source.dart';

/// Bottom sheet listing the audio and subtitle tracks the [Player] has
/// detected. Tapping a row tells media_kit to switch tracks and pops the
/// sheet. The selected row is highlighted via a check mark.
///
/// We watch [Player.stream.tracks] / [Player.stream.track] so the list and
/// selection stay live: e.g. an HLS stream that adds tracks mid-playback
/// will show up automatically the next time the sheet is opened (or while
/// it's open, since [StreamBuilder] rebuilds).
class TracksSheet extends StatelessWidget {
  const TracksSheet({
    super.key,
    required this.player,
    required this.sourceListenable,
    required this.selectedExternalSubListenable,
    required this.onSelectExternalSubtitle,
    required this.onSetSubVisibility,
  });

  final Player player;

  /// Live source — driven by a [ValueNotifier] in the player screen so the
  /// external-subs list refreshes if the sheet opened *before* PlaybackInfo
  /// finished resolving (small but real timing window).
  final ValueListenable<StreamSource?> sourceListenable;

  /// Live external-sub selection. Same pattern.
  final ValueListenable<String?> selectedExternalSubListenable;

  final ValueChanged<ExternalSubtitle?> onSelectExternalSubtitle;
  final ValueChanged<bool> onSetSubVisibility;

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
              return ValueListenableBuilder<StreamSource?>(
                valueListenable: sourceListenable,
                builder: (context, source, _) {
                  return ValueListenableBuilder<String?>(
                    valueListenable: selectedExternalSubListenable,
                    builder: (context, selectedExternalSubId, child) {
                      final tracks = tracksSnap.data ?? player.state.tracks;
                      final current = currentSnap.data ?? player.state.track;
                      final externalSubs =
                          source?.externalSubtitles ?? const [];
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
                                externalSubtitles: externalSubs,
                                selectedExternalSubId: selectedExternalSubId,
                                onSelectExternalSubtitle:
                                    onSelectExternalSubtitle,
                                onSetSubVisibility: onSetSubVisibility,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
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
        .where(
          (t) => t.id != AudioTrack.auto().id && t.id != AudioTrack.no().id,
        )
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

  String _audioLabel(AudioTrack t) => _trackDisplayLabel(
    title: t.title,
    language: t.language,
    fallbackId: t.id,
  );
}

class _SubtitleSection extends StatelessWidget {
  const _SubtitleSection({
    required this.player,
    required this.tracks,
    required this.current,
    required this.externalSubtitles,
    required this.selectedExternalSubId,
    required this.onSelectExternalSubtitle,
    required this.onSetSubVisibility,
  });

  final Player player;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack current;
  final List<ExternalSubtitle> externalSubtitles;
  final String? selectedExternalSubId;
  final ValueChanged<ExternalSubtitle?> onSelectExternalSubtitle;
  final ValueChanged<bool> onSetSubVisibility;

  @override
  Widget build(BuildContext context) {
    final embedded = tracks
        .where(
          (t) =>
              t.id != SubtitleTrack.auto().id && t.id != SubtitleTrack.no().id,
        )
        .toList();
    final hasExternal = selectedExternalSubId != null;
    final isOff = current.id == SubtitleTrack.no().id && !hasExternal;
    final hasAny = embedded.isNotEmpty || externalSubtitles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Subtitles'),
        _TrackRow(
          label: 'Off',
          selected: isOff,
          onTap: () {
            onSelectExternalSubtitle(null);
            player.setSubtitleTrack(SubtitleTrack.no());
            onSetSubVisibility(false);
            Navigator.of(context).pop();
          },
        ),
        if (!hasAny)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'No subtitle tracks available.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ),
        for (final t in embedded)
          _TrackRow(
            label: _embeddedLabel(t),
            selected: !hasExternal && !isOff && t.id == current.id,
            onTap: () {
              // Picking an embedded track clears any external selection.
              onSelectExternalSubtitle(null);
              player.setSubtitleTrack(t);
              onSetSubVisibility(true);
              Navigator.of(context).pop();
            },
          ),
        for (final sub in externalSubtitles)
          _TrackRow(
            label: '${_externalLabel(sub)} (external)',
            selected: hasExternal && sub.id == selectedExternalSubId,
            onTap: () {
              onSelectExternalSubtitle(sub);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  String _embeddedLabel(SubtitleTrack t) => _trackDisplayLabel(
    title: t.title,
    language: t.language,
    fallbackId: t.id,
  );

  String _externalLabel(ExternalSubtitle sub) {
    return _trackDisplayLabel(
      title: sub.title,
      language: sub.language,
      fallbackId: sub.codec ?? 'subs',
    );
  }
}

/// Builds a friendly label for an audio/subtitle track.
///
/// Priority: server-provided title → ISO 639 → raw language code → "Track {id}".
/// Returns the placeholder for empty everything so the row is never blank.
String _trackDisplayLabel({
  required String? title,
  required String? language,
  required String fallbackId,
}) {
  final t = title?.trim();
  if (t != null && t.isNotEmpty) {
    // If the title already encodes the language (mpv often emits "English (eng)"),
    // skip the redundant trailing code.
    final mapped = languageDisplay(language);
    if (mapped != null && t.toLowerCase() != mapped.toLowerCase()) {
      return '$t · $mapped';
    }
    return t;
  }
  final mapped = languageDisplay(language);
  if (mapped != null) return mapped;
  // Last-resort: a normalised raw code, never the literal "und".
  final raw = language?.trim();
  if (raw != null && raw.isNotEmpty && raw.toLowerCase() != 'und') {
    return raw;
  }
  return fallbackId.isEmpty ? 'Track' : 'Track $fallbackId';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => AppGradients.accent.createShader(bounds),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.surfaceHighlight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
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
        ),
      ),
    );
  }
}
