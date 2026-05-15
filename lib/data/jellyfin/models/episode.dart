import 'browse_item.dart';
import 'person_credit.dart';

class Episode {
  const Episode({
    required this.id,
    required this.name,
    required this.seriesId,
    this.seasonId,
    this.seriesName,
    this.tagline,
    this.overview,
    this.indexNumber,
    this.parentIndexNumber,
    this.runTime,
    this.imageTag,
    this.userData,
    this.communityRating,
    this.premiereDate,
    this.artists = const [],
  });

  final String id;
  final String name;
  final String seriesId;
  final String? seasonId;
  final String? seriesName;
  final String? tagline;
  final String? overview;

  /// Episode number within the season (1-based).
  final int? indexNumber;

  /// Season number this episode belongs to.
  final int? parentIndexNumber;

  final Duration? runTime;
  final String? imageTag;
  final UserData? userData;
  final double? communityRating;

  /// Air date — when available, used as a small caption beneath the title.
  final DateTime? premiereDate;

  /// Cast & crew credits attached to this episode (Jellyfin returns the
  /// same `People[]` shape it does on movies and series).
  final List<PersonCredit> artists;

  String get shortLabel {
    if (parentIndexNumber == null || indexNumber == null) return '';
    final ep = indexNumber!.toString().padLeft(2, '0');
    return 'S$parentIndexNumber · E$ep';
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final tags = json['ImageTags'];
    final people =
        (json['People'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final taglines =
        (json['Taglines'] as List?)?.cast<String>() ?? const <String>[];
    final firstTagline = taglines.firstWhere(
      (tagline) => tagline.trim().isNotEmpty,
      orElse: () => '',
    );
    final premiere = json['PremiereDate'] as String?;
    return Episode(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Episode',
      seriesId: json['SeriesId'] as String? ?? '',
      seasonId: json['SeasonId'] as String?,
      seriesName: json['SeriesName'] as String?,
      tagline: firstTagline.isNotEmpty
          ? firstTagline
          : (json['Tagline'] as String?),
      overview: json['Overview'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      runTime: ticks != null ? Duration(microseconds: ticks ~/ 10) : null,
      imageTag: (tags is Map && tags['Primary'] is String)
          ? tags['Primary'] as String
          : null,
      userData: json['UserData'] is Map<String, dynamic>
          ? UserData.fromJson(json['UserData'] as Map<String, dynamic>)
          : null,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      premiereDate: premiere != null ? DateTime.tryParse(premiere) : null,
      artists: people
          .map(PersonCredit.fromJson)
          .where((person) => person.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}
