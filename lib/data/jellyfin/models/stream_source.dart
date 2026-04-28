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
  });

  final String url;
  final bool isTranscoding;
  final String? playSessionId;
  final String? mediaSourceId;

  /// What the scrobbler should report as `PlayMethod` to Jellyfin.
  String get playMethod => isTranscoding ? 'Transcode' : 'DirectStream';
}
