/// Skippable ranges from the Jellyfin **Intro Skipper** plugin (or compatible
/// forks). Times are relative to the start of the media file.
///
/// When the plugin is absent or has no analysis for the item, the repository
/// returns `null` — callers should treat that as a no-op.
class IntroSkipperTimestamps {
  const IntroSkipperTimestamps({this.introduction, this.credits});

  /// Opening title / cold-open skip range, if detected.
  final IntroSkipperRange? introduction;

  /// End-credits / post-roll skip range, if detected.
  final IntroSkipperRange? credits;

  bool get hasAny => introduction != null || credits != null;

  /// `GET …/Episode/{id}/Timestamps` (intro-skipper fork ≥ ~10.x).
  factory IntroSkipperTimestamps.fromPluginTimestampsJson(
    Map<String, dynamic> json,
  ) {
    return IntroSkipperTimestamps(
      introduction: IntroSkipperRange.parseSegmentJson(
        json['Introduction'] ?? json['introduction'],
      ),
      credits: IntroSkipperRange.parseSegmentJson(
        json['Credits'] ?? json['credits'] ?? json['Outro'] ?? json['outro'],
      ),
    );
  }

  /// `GET …/Episode/{id}/IntroTimestamps/v1` (original plugin schema).
  factory IntroSkipperTimestamps.fromLegacyIntroV1Json(
    Map<String, dynamic> json,
  ) {
    final start = _readNonNegativeSeconds(
      json['IntroStart'] ?? json['introStart'],
    );
    final end = _readNonNegativeSeconds(json['IntroEnd'] ?? json['introEnd']);
    if (start == null || end == null || end <= start) {
      return const IntroSkipperTimestamps();
    }
    return IntroSkipperTimestamps(
      introduction: IntroSkipperRange(start: start, end: end),
    );
  }

  /// Fills in missing segments from [other] (e.g. merge legacy intro-only).
  IntroSkipperTimestamps mergePreferNonNull(IntroSkipperTimestamps other) {
    return IntroSkipperTimestamps(
      introduction: introduction ?? other.introduction,
      credits: credits ?? other.credits,
    );
  }
}

class IntroSkipperRange {
  const IntroSkipperRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  /// True when [position] lies inside `[start, end)`.
  bool contains(Duration position) => position >= start && position < end;

  static IntroSkipperRange? parseSegmentJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final start = _readNonNegativeSeconds(m['Start'] ?? m['start']);
    final end = _readNonNegativeSeconds(m['End'] ?? m['end']);
    if (start == null || end == null || end <= start || end <= Duration.zero) {
      return null;
    }
    return IntroSkipperRange(start: start, end: end);
  }
}

Duration? _readNonNegativeSeconds(dynamic v) {
  if (v is String) {
    final parsed = double.tryParse(v.trim());
    if (parsed == null) return null;
    v = parsed;
  }
  if (v is! num) return null;
  if (v.toDouble() < 0) return null;
  return Duration(microseconds: (v.toDouble() * 1000000).round());
}
