enum MediaKind { movie, series, season, episode, person, collection }

MediaKind? _kindFromJellyfinType(String? type) {
  switch (type) {
    case 'Movie':
      return MediaKind.movie;
    case 'Series':
      return MediaKind.series;
    case 'Season':
      return MediaKind.season;
    case 'Episode':
      return MediaKind.episode;
    case 'Person':
      return MediaKind.person;
    case 'BoxSet':
      return MediaKind.collection;
    default:
      return null;
  }
}

Duration _durationFromTicks(int? ticks) {
  if (ticks == null) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

/// Generic poster/list item for media, people, and collections.
class BrowseItem {
  const BrowseItem({
    required this.id,
    required this.name,
    required this.kind,
    this.subtitle,
    this.imageTag,
    this.backdropTag,
    this.runTime,
    this.childCount,
    this.year,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.userData,
  });

  final String id;
  final String name;
  final MediaKind kind;

  /// One-line caption shown beneath the title (year, season/episode, etc.).
  final String? subtitle;

  /// Tag for `Items/{id}/Images/Primary` cache-busting.
  final String? imageTag;
  final String? backdropTag;

  final Duration? runTime;
  final int? childCount;
  final int? year;

  // Episode-only metadata.
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  final UserData? userData;

  BrowseItem copyWithChildCount(int? count) {
    return BrowseItem(
      id: id,
      name: name,
      kind: kind,
      subtitle: _subtitleFor(
        kind: kind,
        year: year,
        childCount: count,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
      imageTag: imageTag,
      backdropTag: backdropTag,
      runTime: runTime,
      childCount: count,
      year: year,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      userData: userData,
    );
  }

  factory BrowseItem.fromJson(Map<String, dynamic> json) {
    final type = json['Type'] as String?;
    final kind = _kindFromJellyfinType(type) ?? MediaKind.movie;
    final year = json['ProductionYear'] as int?;
    final season = json['ParentIndexNumber'] as int?;
    final episode = json['IndexNumber'] as int?;
    final childCount = _intFromJson(json['ChildCount']);

    return BrowseItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      kind: kind,
      subtitle: _subtitleFor(
        kind: kind,
        year: year,
        childCount: childCount,
        seasonNumber: season,
        episodeNumber: episode,
      ),
      imageTag: _primaryImageTag(json),
      backdropTag: _backdropImageTag(json),
      runTime: json['RunTimeTicks'] != null
          ? _durationFromTicks(json['RunTimeTicks'] as int?)
          : null,
      childCount: childCount,
      year: year,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonNumber: season,
      episodeNumber: episode,
      userData: json['UserData'] is Map<String, dynamic>
          ? UserData.fromJson(json['UserData'] as Map<String, dynamic>)
          : null,
    );
  }
}

String? _subtitleFor({
  required MediaKind kind,
  required int? year,
  required int? childCount,
  required int? seasonNumber,
  required int? episodeNumber,
}) {
  switch (kind) {
    case MediaKind.movie:
      return year?.toString();
    case MediaKind.series:
      final parts = [
        if (year != null) year.toString(),
        if (childCount != null && childCount > 0)
          '$childCount season${childCount == 1 ? '' : 's'}',
      ];
      return parts.isEmpty ? null : parts.join(' • ');
    case MediaKind.season:
      return seasonNumber != null ? 'Season $seasonNumber' : null;
    case MediaKind.episode:
      if (seasonNumber != null && episodeNumber != null) {
        final padded = episodeNumber.toString().padLeft(2, '0');
        return 'S$seasonNumber · E$padded';
      }
      return null;
    case MediaKind.person:
      return null;
    case MediaKind.collection:
      return childCount == null
          ? null
          : '$childCount item${childCount == 1 ? '' : 's'}';
  }
}

int? _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Per-user playback state attached to any video item.
class UserData {
  const UserData({
    this.played = false,
    this.isFavorite = false,
    this.playbackPositionTicks = 0,
    this.playedPercentage,
  });

  final bool played;
  final bool isFavorite;
  final int playbackPositionTicks;
  final double? playedPercentage;

  Duration get resumePosition =>
      Duration(microseconds: playbackPositionTicks ~/ 10);

  /// Fraction in [0, 1] for progress bars.
  double get progress {
    final pct = playedPercentage;
    if (pct == null) return 0;
    return (pct / 100).clamp(0, 1);
  }

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      played: json['Played'] as bool? ?? false,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      playbackPositionTicks: json['PlaybackPositionTicks'] as int? ?? 0,
      playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble(),
    );
  }
}

String? _primaryImageTag(Map<String, dynamic> json) {
  final tags = json['ImageTags'];
  if (tags is Map && tags['Primary'] is String) {
    return tags['Primary'] as String;
  }
  return null;
}

String? _backdropImageTag(Map<String, dynamic> json) {
  final list = json['BackdropImageTags'];
  if (list is List && list.isNotEmpty && list.first is String) {
    return list.first as String;
  }
  return null;
}
