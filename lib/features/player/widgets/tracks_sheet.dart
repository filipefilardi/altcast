import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:media_kit/media_kit.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/utils/language.dart';
import 'package:altcast/data/jellyfin/models/media_stream.dart';
import 'package:altcast/data/jellyfin/models/stream_source.dart';

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
    required this.onSelectSubtitleOff,
    required this.onSelectSubtitleStream,
    required this.onSelectEmbeddedSubtitle,
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

  final VoidCallback onSelectSubtitleOff;
  final ValueChanged<MediaStream> onSelectSubtitleStream;
  final ValueChanged<SubtitleTrack> onSelectEmbeddedSubtitle;
  final ValueChanged<ExternalSubtitle> onSelectExternalSubtitle;
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
                      final jellyfinSubs = source?.subtitleStreams ?? const [];
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
                                jellyfinSubtitles: jellyfinSubs,
                                externalSubtitles: externalSubs,
                                selectedExternalSubId: selectedExternalSubId,
                                onSelectSubtitleOff: onSelectSubtitleOff,
                                onSelectSubtitleStream: onSelectSubtitleStream,
                                onSelectEmbeddedSubtitle:
                                    onSelectEmbeddedSubtitle,
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
    required this.jellyfinSubtitles,
    required this.externalSubtitles,
    required this.selectedExternalSubId,
    required this.onSelectSubtitleOff,
    required this.onSelectSubtitleStream,
    required this.onSelectEmbeddedSubtitle,
    required this.onSelectExternalSubtitle,
    required this.onSetSubVisibility,
  });

  final Player player;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack current;
  final List<MediaStream> jellyfinSubtitles;
  final List<ExternalSubtitle> externalSubtitles;
  final String? selectedExternalSubId;
  final VoidCallback onSelectSubtitleOff;
  final ValueChanged<MediaStream> onSelectSubtitleStream;
  final ValueChanged<SubtitleTrack> onSelectEmbeddedSubtitle;
  final ValueChanged<ExternalSubtitle> onSelectExternalSubtitle;
  final ValueChanged<bool> onSetSubVisibility;

  @override
  Widget build(BuildContext context) {
    final jellyfinRows = _jellyfinSubtitleRows(jellyfinSubtitles);
    final selectedJellyfinIndex = _selectedJellyfinSubtitleIndex(
      current: current,
      externalTracks: externalSubtitles,
      selectedExternalSubId: selectedExternalSubId,
    );
    if (jellyfinRows.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(label: 'Subtitles'),
          _TrackRow(
            label: 'Off',
            selected: selectedJellyfinIndex == null,
            onTap: () {
              onSelectSubtitleOff();
              onSetSubVisibility(false);
              Navigator.of(context).pop();
            },
          ),
          for (final row in jellyfinRows)
            _TrackRow(
              label: row.label,
              selected: selectedJellyfinIndex == row.stream.index,
              onTap: () {
                onSelectSubtitleStream(row.stream);
                Navigator.of(context).pop();
              },
            ),
        ],
      );
    }

    final hasCanonicalSubtitles = externalSubtitles.isNotEmpty;
    final embedded = hasCanonicalSubtitles
        ? const <SubtitleTrack>[]
        : tracks
              .where(
                (t) =>
                    t.id != SubtitleTrack.auto().id &&
                    t.id != SubtitleTrack.no().id,
              )
              .toList();
    final filteredExternal = _filterExternalSubtitles(
      externalTracks: externalSubtitles,
    );
    final effectiveExternalSubId =
        selectedExternalSubId ??
        _inferExternalSelectionFromCurrent(
          current: current,
          externalTracks: filteredExternal,
        );
    final hasExternal = effectiveExternalSubId != null;
    final selectedEmbeddedId = _resolveEmbeddedSelectionId(
      current: current,
      embeddedTracks: embedded,
      hasExternalSelection: hasExternal,
    );
    final isOff =
        current.id == SubtitleTrack.no().id &&
        !hasExternal &&
        selectedEmbeddedId == null;
    final hasAny = embedded.isNotEmpty || filteredExternal.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Subtitles'),
        _TrackRow(
          label: 'Off',
          selected: isOff,
          onTap: () {
            onSelectSubtitleOff();
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
            selected: selectedEmbeddedId != null && t.id == selectedEmbeddedId,
            onTap: () {
              // Picking an embedded track clears any external selection.
              onSelectEmbeddedSubtitle(t);
              onSetSubVisibility(true);
              Navigator.of(context).pop();
            },
          ),
        for (final sub in filteredExternal)
          _TrackRow(
            label: _externalLabel(sub),
            selected: hasExternal && sub.id == effectiveExternalSubId,
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
    final label = _trackDisplayLabel(
      title: sub.title,
      language: sub.language,
      fallbackId: sub.codec ?? 'subs',
    );
    final extra = [
      if (sub.isForced) 'Forced',
      if (sub.isHearingImpaired) 'SDH',
    ];
    if (extra.isEmpty) return label;
    return '$label · ${extra.join(' · ')}';
  }

  List<_JellyfinSubtitleRow> _jellyfinSubtitleRows(List<MediaStream> streams) {
    final labels = [
      for (final stream in streams) _jellyfinSubtitleLabel(stream),
    ];
    final labelCounts = <String, int>{};
    for (final label in labels) {
      final key = label.toLowerCase();
      labelCounts[key] = (labelCounts[key] ?? 0) + 1;
    }

    return [
      for (var i = 0; i < streams.length; i++)
        _JellyfinSubtitleRow(
          stream: streams[i],
          label: (labelCounts[labels[i].toLowerCase()] ?? 0) > 1
              ? '${labels[i]} · Track ${streams[i].index}'
              : labels[i],
        ),
    ];
  }

  String _jellyfinSubtitleLabel(MediaStream stream) {
    final descriptor = _subtitleTitleDescriptor(stream);
    final extras = <String>[
      if (stream.isForced) 'Forced',
      if (stream.isHearingImpaired) 'SDH',
      ?descriptor,
    ];
    final mapped =
        languageDisplay(stream.language) ?? stream.language ?? 'Track';
    if (extras.isEmpty) return mapped;
    return '$mapped · ${extras.join(' · ')}';
  }

  String? _subtitleTitleDescriptor(MediaStream stream) {
    final raw = (stream.displayTitle ?? stream.title ?? '').trim();
    if (raw.isEmpty) return null;

    var normalized = raw.toLowerCase();
    for (final token in [
      languageDisplay(stream.language),
      stream.language,
      stream.codec,
      'subtitle',
      'subtitles',
      'subrip',
      'default',
      'external',
      'utf-8',
    ]) {
      final value = token?.trim().toLowerCase();
      if (value == null || value.isEmpty) continue;
      normalized = normalized.replaceAll(value, ' ');
    }
    normalized = normalized
        .replaceAll(RegExp(r'[\[\]\(\)\-_/·•]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;
    if (normalized == 'sdh') return 'SDH';
    if (normalized == 'cc') return 'CC';
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part.length <= 3 ? part.toUpperCase() : _titleCase(part))
        .join(' ');
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  int? _selectedJellyfinSubtitleIndex({
    required SubtitleTrack current,
    required List<ExternalSubtitle> externalTracks,
    required String? selectedExternalSubId,
  }) {
    if (selectedExternalSubId != null) {
      for (final subtitle in externalTracks) {
        if (subtitle.id == selectedExternalSubId) return subtitle.streamIndex;
      }
    }
    if (current.id == SubtitleTrack.no().id ||
        current.id == SubtitleTrack.auto().id) {
      return null;
    }
    final parsed = int.tryParse(current.id);
    if (parsed != null) return parsed;
    final inferredExternalId = _inferExternalSelectionFromCurrent(
      current: current,
      externalTracks: externalTracks,
    );
    if (inferredExternalId == null) return null;
    for (final subtitle in externalTracks) {
      if (subtitle.id == inferredExternalId) return subtitle.streamIndex;
    }
    return null;
  }

  List<ExternalSubtitle> _filterExternalSubtitles({
    required List<ExternalSubtitle> externalTracks,
  }) {
    if (externalTracks.isEmpty) return const [];

    final seenExternalKeys = <String>{};
    final out = <ExternalSubtitle>[];

    for (final sub in externalTracks) {
      final externalKeys = {
        if (sub.streamIndex != null)
          'index:${sub.streamIndex}'
        else
          'id:${sub.id}',
      };
      final duplicatesExternal = externalKeys.any(seenExternalKeys.contains);
      if (duplicatesExternal) continue;
      seenExternalKeys.addAll(externalKeys);
      out.add(sub);
    }
    return out;
  }

  String? _inferExternalSelectionFromCurrent({
    required SubtitleTrack current,
    required List<ExternalSubtitle> externalTracks,
  }) {
    if (externalTracks.isEmpty) return null;
    if (current.id == SubtitleTrack.no().id ||
        current.id == SubtitleTrack.auto().id) {
      return null;
    }
    final currentTitle = _normalizeTitle(current.title);
    if (currentTitle == null) return null;
    for (final sub in externalTracks) {
      if (_normalizeTitle(sub.title) == currentTitle) return sub.id;
    }
    return null;
  }

  String? _resolveEmbeddedSelectionId({
    required SubtitleTrack current,
    required List<SubtitleTrack> embeddedTracks,
    required bool hasExternalSelection,
  }) {
    if (hasExternalSelection || embeddedTracks.isEmpty) return null;
    for (final t in embeddedTracks) {
      if (t.id == current.id) return t.id;
    }
    final currentTitle = _normalizeTitle(current.title);
    if (currentTitle != null) {
      for (final t in embeddedTracks) {
        if (_normalizeTitle(t.title) == currentTitle) return t.id;
      }
    }
    // mpv sometimes reports "auto" as current id while one embedded track is
    // effectively active. If there is only one option, mark it selected.
    if (current.id == SubtitleTrack.auto().id && embeddedTracks.length == 1) {
      return embeddedTracks.first.id;
    }
    return null;
  }

  String? _normalizeTitle(String? title) {
    final raw = title?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    // Remove punctuation-like separators to collapse minor formatting variants.
    final compact = raw.replaceAll(RegExp(r'[\s\-\._\(\)\[\]]+'), '');
    return compact.isEmpty ? null : compact;
  }
}

class _JellyfinSubtitleRow {
  const _JellyfinSubtitleRow({required this.stream, required this.label});

  final MediaStream stream;
  final String label;
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
                  const Icon(
                    PiconsRegular.check,
                    size: 18,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
