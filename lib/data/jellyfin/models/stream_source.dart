/// Result of negotiating playback with Jellyfin's `PlaybackInfo` endpoint.
///
/// Two flavours, distinguished by [isTranscoding]:
/// - **DirectStream / DirectPlay** → [url] is the static `/Videos/{id}/stream`
///   endpoint. Server sends original bytes (or remuxes), playback is instant
///   and seek is cheap.
/// - **Transcoding** → [url] is an HLS master playlist. Server transcodes on
///   the fly. Seek triggers a re-transcode; quality is server-decided.
class StreamSource {
  const StreamSource({
    required this.url,
    required this.isTranscoding,
    this.playSessionId,
    this.mediaSourceId,
    this.externalSubtitles = const [],
  });

  final String url;
  final bool isTranscoding;
  final String? playSessionId;
  final String? mediaSourceId;

  /// Sidecar subtitle files (`.srt`/`.vtt`/etc.) Jellyfin serves separately
  /// from the main stream. media_kit doesn't auto-discover these, so the
  /// player layer has to register each one and surface it in the picker.
  final List<ExternalSubtitle> externalSubtitles;

  /// What the scrobbler should report as `PlayMethod` to Jellyfin.
  String get playMethod => isTranscoding ? 'Transcode' : 'DirectStream';
}

/// A subtitle stream that lives outside the main media file. Carries enough
/// info for media_kit's `SubtitleTrack.uri(...)` plus a stable [id] we can
/// match against the player's reported current subtitle.
class ExternalSubtitle {
  const ExternalSubtitle({
    required this.id,
    required this.url,
    this.title,
    this.language,
    this.codec,
  });

  /// Stable identifier (we use the absolute URL — unique per source).
  final String id;
  final String url;

  /// Server-provided display title (e.g. "English (SDH)"). Often null.
  final String? title;

  /// Raw ISO 639 code (e.g. `"eng"`, `"spa"`). Pass through
  /// [languageDisplay] before showing in UI.
  final String? language;

  /// `srt` / `vtt` / `ass` / etc. — handy as a last-resort label.
  final String? codec;
}
