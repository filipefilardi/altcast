/// One audio or subtitle stream as Jellyfin reports it on the item endpoint.
///
/// Used by the pre-play picker on detail screens — we want to show the user
/// what's available before [JellyfinRepository.getStreamSource] gets called
/// (which spins up a transcoder when needed). The fields here mirror the
/// MediaStream shape from `/Items/{id}` precisely enough to drive a picker
/// without round-tripping more data.
class MediaStream {
  const MediaStream({
    required this.index,
    required this.kind,
    this.title,
    this.displayTitle,
    this.language,
    this.codec,
    this.channels,
    this.isDefault = false,
    this.isExternal = false,
  });

  /// Stream index within the source. Stable across calls.
  final int index;
  final MediaStreamKind kind;

  /// Server-provided "DisplayTitle" (preferred for the picker label).
  final String? displayTitle;

  /// Raw Title (sometimes more concise than DisplayTitle).
  final String? title;

  /// ISO 639-1/2/3 code. Pass through `languageDisplay` before showing.
  final String? language;
  final String? codec;
  final int? channels;
  final bool isDefault;
  final bool isExternal;

  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      index: json['Index'] as int? ?? -1,
      kind: _kindFromType(json['Type'] as String?),
      title: json['Title'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      language: json['Language'] as String?,
      codec: (json['Codec'] as String?)?.toLowerCase(),
      channels: json['Channels'] as int?,
      isDefault: json['IsDefault'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
    );
  }
}

enum MediaStreamKind { audio, subtitle, video, unknown }

MediaStreamKind _kindFromType(String? type) {
  switch (type) {
    case 'Audio':
      return MediaStreamKind.audio;
    case 'Subtitle':
      return MediaStreamKind.subtitle;
    case 'Video':
      return MediaStreamKind.video;
    default:
      return MediaStreamKind.unknown;
  }
}

/// Tracks-only summary of an item — what the pre-play picker shows.
class ItemMediaStreams {
  const ItemMediaStreams({required this.audio, required this.subtitle});

  final List<MediaStream> audio;
  final List<MediaStream> subtitle;

  bool get hasAudio => audio.isNotEmpty;
  bool get hasSubtitle => subtitle.isNotEmpty;

  /// First stream marked as the server-side default, or the first stream of
  /// the kind at all. Useful for the picker's initial value.
  MediaStream? defaultAudio() {
    if (audio.isEmpty) return null;
    return audio.firstWhere((s) => s.isDefault, orElse: () => audio.first);
  }

  /// Server-selected subtitle stream when Jellyfin marks one. If there is only
  /// one subtitle, expose it so a single-option detail picker can still show
  /// the language instead of a generic auto label.
  MediaStream? defaultSubtitle() {
    if (subtitle.isEmpty) return null;
    for (final stream in subtitle) {
      if (stream.isDefault) return stream;
    }
    return subtitle.length == 1 ? subtitle.first : null;
  }
}
