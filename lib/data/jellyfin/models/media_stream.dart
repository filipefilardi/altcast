/// One subtitle stream as Jellyfin reports it on the negotiated media source.
///
/// Drives the player's subtitle picker. The fields mirror the Jellyfin
/// `MediaStream` shape precisely enough to label and select a track while
/// sharing the same negotiated subtitle source as playback.
class MediaStream {
  const MediaStream({
    required this.index,
    this.title,
    this.displayTitle,
    this.language,
    this.codec,
    this.isExternal = false,
    this.deliveryMethod,
    this.isForced = false,
    this.isHearingImpaired = false,
  });

  /// Stream index within the source. Stable across calls.
  final int index;

  /// Server-provided "DisplayTitle" (preferred for the picker label).
  final String? displayTitle;

  /// Raw Title (sometimes more concise than DisplayTitle).
  final String? title;

  /// ISO 639-1/2/3 code. Pass through `languageDisplay` before showing.
  final String? language;
  final String? codec;
  final bool isExternal;
  final String? deliveryMethod;
  final bool isForced;
  final bool isHearingImpaired;

  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      index: json['Index'] as int? ?? -1,
      title: json['Title'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      language: json['Language'] as String?,
      codec: (json['Codec'] as String?)?.toLowerCase(),
      isExternal: json['IsExternal'] as bool? ?? false,
      deliveryMethod: json['DeliveryMethod'] as String?,
      isForced: json['IsForced'] as bool? ?? false,
      isHearingImpaired: json['IsHearingImpaired'] as bool? ?? false,
    );
  }
}
