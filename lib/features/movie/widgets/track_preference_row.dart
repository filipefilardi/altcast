import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/language.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/media_stream.dart';
import 'package:altcast/data/local/playback_preferences.dart';

/// Per-play user preferences captured by [TrackPreferenceRow] and forwarded
/// to the player as query params on `/play/:id`.
///
/// Conventions:
///  - `audioLang == null` → server/player default (no override).
///  - `subKind == _SubKind.off` → explicitly disable subtitles.
///  - `subKind == _SubKind.byLang` → match a sub track with this language.
///    When available, `subStreamIndex` pins that to the exact Jellyfin stream.
class TrackPreference {
  const TrackPreference({
    this.audioLang,
    this.subKind = SubPreferenceKind.serverDefault,
    this.subLang,
    this.subStreamIndex,
  });

  /// Seeds a per-item preference from the user's global playback defaults,
  /// resolving the audio language against the item's original language so
  /// "Original" maps to the right ISO code.
  factory TrackPreference.fromPlaybackPrefs(
    PlaybackPreferences prefs, {
    String? itemOriginalLanguage,
  }) {
    return TrackPreference(
      audioLang: prefs.resolvedAudioLanguage(itemOriginalLanguage),
      subKind: switch (prefs.defaultSubtitleMode) {
        DefaultSubtitleMode.auto => SubPreferenceKind.off,
        DefaultSubtitleMode.off => SubPreferenceKind.off,
        DefaultSubtitleMode.byLanguage => SubPreferenceKind.byLang,
      },
      subLang: prefs.defaultSubtitleLanguage,
    );
  }

  final String? audioLang;
  final SubPreferenceKind subKind;
  final String? subLang;
  final int? subStreamIndex;

  /// Encode into the `?audioLang=...&subLang=...` query string the player
  /// reads. Empty pieces are omitted.
  Map<String, String> toQuery() {
    final q = <String, String>{};
    if (audioLang != null && audioLang!.isNotEmpty) {
      q['audioLang'] = audioLang!;
    }
    switch (subKind) {
      case SubPreferenceKind.serverDefault:
        break;
      case SubPreferenceKind.off:
        q['subLang'] = 'off';
      case SubPreferenceKind.byLang:
        if (subLang != null && subLang!.isNotEmpty) {
          q['subLang'] = subLang!;
        }
        if (subStreamIndex != null) {
          q['subIndex'] = '$subStreamIndex';
        }
    }
    return q;
  }
}

enum SubPreferenceKind { serverDefault, off, byLang }

/// A compact control card under the Play button with Audio/Subtitles selectors.
/// Tapping opens a bottom sheet picker filled from
/// [JellyfinRepository.getMediaStreams].
///
/// Quietly renders nothing while streams are loading. The audio pill is shown
/// whenever there is at least one audio stream so the language is visible
/// without starting playback.
class TrackPreferenceRow extends ConsumerWidget {
  const TrackPreferenceRow({
    super.key,
    required this.itemId,
    required this.preference,
    required this.onChanged,
    this.originalLanguageHint,
  });

  final String itemId;
  final TrackPreference preference;
  final ValueChanged<TrackPreference> onChanged;

  /// ISO language code from Jellyfin metadata (TMDB original language / tags).
  final String? originalLanguageHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamsAsync = ref.watch(_streamsProvider(itemId));
    return streamsAsync.when(
      data: (streams) {
        final hint = originalLanguageHint?.trim();
        final hasOriginalHint = hint != null && hint.isNotEmpty;
        final showAudio = streams.audio.isNotEmpty;
        final showSubs = streams.subtitle.isNotEmpty;
        final canPickAudio = streams.audio.length > 1;
        final canPickSubs = streams.subtitle.length > 1;
        if (!showAudio && !showSubs) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUDIO & SUBTITLES',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (hasOriginalHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Original audio: ${languageDisplay(hint) ?? hint}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (showAudio)
                      Expanded(
                        child: _TrackTile(
                          icon: PiconsRegular.speakerHigh,
                          title: 'Audio',
                          value: _audioLabel(streams),
                          onTap: canPickAudio
                              ? () => _pickAudio(context, streams)
                              : null,
                        ),
                      ),
                    if (showAudio && showSubs) const SizedBox(width: 8),
                    if (showSubs)
                      Expanded(
                        child: _TrackTile(
                          icon: PiconsRegular.closedCaptioning,
                          title: 'Subtitles',
                          value: _subLabel(streams),
                          onTap: canPickSubs
                              ? () => _pickSub(context, streams)
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      // Streams fetch is cosmetic — if it fails, the in-player picker still
      // works. Don't show an error state on the detail screen.
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  String _audioLabel(ItemMediaStreams streams) {
    final lang = preference.audioLang;
    if (lang == null) {
      final def = streams.defaultAudio();
      return _streamLabel(def, fallback: 'Auto');
    }
    final match = streams.audio.firstWhere(
      (s) => (s.language ?? '').toLowerCase() == lang.toLowerCase(),
      orElse: () => streams.audio.first,
    );
    return _streamLabel(match, fallback: lang);
  }

  String _subLabel(ItemMediaStreams streams) {
    switch (preference.subKind) {
      case SubPreferenceKind.serverDefault:
        return _streamLabel(streams.defaultSubtitle(), fallback: 'Auto');
      case SubPreferenceKind.off:
        return 'Off';
      case SubPreferenceKind.byLang:
        final lang = preference.subLang;
        if (lang != null && lang.isNotEmpty) {
          final match = streams.subtitle.firstWhere(
            (s) => (s.language ?? '').toLowerCase() == lang.toLowerCase(),
            orElse: () => streams.subtitle.first,
          );
          return _streamLabel(match, fallback: lang);
        }
        final mapped =
            languageDisplay(preference.subLang) ?? preference.subLang ?? 'On';
        return mapped;
    }
  }

  MediaStream? _selectedAudioStream(ItemMediaStreams streams) {
    final lang = preference.audioLang;
    if (lang == null || lang.isEmpty) return null;
    return streams.audio.firstWhere(
      (s) => (s.language ?? '').toLowerCase() == lang.toLowerCase(),
      orElse: () => streams.audio.first,
    );
  }

  MediaStream? _selectedSubtitleStream(ItemMediaStreams streams) {
    if (preference.subKind != SubPreferenceKind.byLang) return null;
    final index = preference.subStreamIndex;
    if (index != null) {
      for (final stream in streams.subtitle) {
        if (stream.index == index) return stream;
      }
    }
    final lang = preference.subLang;
    if (lang == null || lang.isEmpty) return null;
    return streams.subtitle.firstWhere(
      (s) => (s.language ?? '').toLowerCase() == lang.toLowerCase(),
      orElse: () => streams.subtitle.first,
    );
  }

  String _serverDefaultSubtitleLabel(ItemMediaStreams streams) {
    final label = _streamLabel(streams.defaultSubtitle(), fallback: 'Auto');
    return label == 'Auto' ? 'Server default' : 'Server default ($label)';
  }

  String _streamLabel(MediaStream? s, {required String fallback}) {
    if (s == null) return fallback;
    final mapped = languageDisplay(s.language);
    if (mapped != null) {
      if (s.channels != null && s.channels! > 2) {
        return '$mapped ${s.channels}.0';
      }
      return mapped;
    }
    final raw = (s.displayTitle ?? s.title ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return fallback;
  }

  Future<void> _pickAudio(
    BuildContext context,
    ItemMediaStreams streams,
  ) async {
    final hint = originalLanguageHint?.trim();
    final selectedAudio = _selectedAudioStream(streams);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      showDragHandle: true,
      builder: (sheetCtx) => _PickerSheet(
        title: 'Audio',
        header: hint != null && hint.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Original language (metadata): ${languageDisplay(hint) ?? hint}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              )
            : null,
        rows: [
          _PickerRow(
            label: 'Server default',
            selected: preference.audioLang == null,
            onTap: () {
              onChanged(
                TrackPreference(
                  audioLang: null,
                  subKind: preference.subKind,
                  subLang: preference.subLang,
                  subStreamIndex: preference.subStreamIndex,
                ),
              );
              Navigator.of(sheetCtx).pop();
            },
          ),
          if (hint != null && hint.isNotEmpty)
            _PickerRow(
              label: 'Original (${languageDisplay(hint) ?? hint})',
              selected:
                  preference.audioLang != null &&
                  preference.audioLang!.toLowerCase() == hint.toLowerCase(),
              onTap: () {
                onChanged(
                  TrackPreference(
                    audioLang: hint,
                    subKind: preference.subKind,
                    subLang: preference.subLang,
                    subStreamIndex: preference.subStreamIndex,
                  ),
                );
                Navigator.of(sheetCtx).pop();
              },
            ),
          for (final s in streams.audio)
            _PickerRow(
              label: _audioRowLabel(s),
              selected: selectedAudio != null && selectedAudio.index == s.index,
              onTap: () {
                onChanged(
                  TrackPreference(
                    audioLang: s.language,
                    subKind: preference.subKind,
                    subLang: preference.subLang,
                    subStreamIndex: preference.subStreamIndex,
                  ),
                );
                Navigator.of(sheetCtx).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickSub(BuildContext context, ItemMediaStreams streams) async {
    final selectedSub = _selectedSubtitleStream(streams);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      showDragHandle: true,
      builder: (sheetCtx) => _PickerSheet(
        title: 'Subtitles',
        rows: [
          _PickerRow(
            label: _serverDefaultSubtitleLabel(streams),
            selected: preference.subKind == SubPreferenceKind.serverDefault,
            onTap: () {
              onChanged(
                TrackPreference(
                  audioLang: preference.audioLang,
                  subKind: SubPreferenceKind.serverDefault,
                ),
              );
              Navigator.of(sheetCtx).pop();
            },
          ),
          _PickerRow(
            label: 'Off',
            selected: preference.subKind == SubPreferenceKind.off,
            onTap: () {
              onChanged(
                TrackPreference(
                  audioLang: preference.audioLang,
                  subKind: SubPreferenceKind.off,
                ),
              );
              Navigator.of(sheetCtx).pop();
            },
          ),
          for (final s in streams.subtitle)
            _PickerRow(
              label: _subRowLabel(s),
              selected: selectedSub != null && selectedSub.index == s.index,
              onTap: () {
                onChanged(
                  TrackPreference(
                    audioLang: preference.audioLang,
                    subKind: SubPreferenceKind.byLang,
                    subLang: s.language,
                    subStreamIndex: s.index,
                  ),
                );
                Navigator.of(sheetCtx).pop();
              },
            ),
        ],
      ),
    );
  }

  String _audioRowLabel(MediaStream s) => _streamRowLabel(s, [
    if (s.channels != null) '${s.channels}.0',
    if (s.codec != null) s.codec!,
  ]);

  String _subRowLabel(MediaStream s) => _streamRowLabel(s, [
    if (s.codec != null) s.codec!,
    if (s.isExternal) 'external',
  ]);

  String _streamRowLabel(MediaStream s, List<String> extra) {
    final mapped = languageDisplay(s.language) ?? s.language ?? 'Track';
    if (extra.isEmpty) return mapped;
    return '$mapped · ${extra.join(' · ')}';
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surfaceHighlight.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  PiconsRegular.caretRight,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.rows, this.header});
  final String title;
  final List<_PickerRow> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              // ignore: use_null_aware_elements
              if (header != null) header!,
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
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
    );
  }
}

final _streamsProvider = FutureProvider.autoDispose
    .family<ItemMediaStreams, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getMediaStreams(id);
    });
