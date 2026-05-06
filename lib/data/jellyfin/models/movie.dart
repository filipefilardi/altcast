import 'browse_item.dart';
import 'original_language.dart';
import 'person_credit.dart';

class Movie {
  const Movie({
    required this.id,
    required this.name,
    this.tagline,
    this.overview,
    this.year,
    this.runTime,
    this.genres = const [],
    this.communityRating,
    this.officialRating,
    this.imageTag,
    this.backdropTag,
    this.userData,
    this.artists = const [],
    this.originalLanguage,
  });

  final String id;
  final String name;
  final String? tagline;
  final String? overview;
  final int? year;
  final Duration? runTime;
  final List<String> genres;
  final double? communityRating;

  /// MPAA-style content rating (e.g. PG-13).
  final String? officialRating;

  final String? imageTag;
  final String? backdropTag;
  final UserData? userData;
  final List<PersonCredit> artists;

  /// ISO language code from metadata when available (TMDB original language).
  final String? originalLanguage;

  factory Movie.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final tags = json['ImageTags'];
    final backdrops = json['BackdropImageTags'];
    final people = (json['People'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final taglines = (json['Taglines'] as List?)?.cast<String>() ?? const <String>[];
    final firstTagline = taglines.firstWhere(
      (tagline) => tagline.trim().isNotEmpty,
      orElse: () => '',
    );
    return Movie(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      tagline: firstTagline.isNotEmpty
          ? firstTagline
          : (json['Tagline'] as String?),
      overview: json['Overview'] as String?,
      year: json['ProductionYear'] as int?,
      runTime: ticks != null
          ? Duration(microseconds: ticks ~/ 10)
          : null,
      genres: (json['Genres'] as List?)?.cast<String>() ?? const [],
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: json['OfficialRating'] as String?,
      imageTag: (tags is Map && tags['Primary'] is String)
          ? tags['Primary'] as String
          : null,
      backdropTag: (backdrops is List && backdrops.isNotEmpty)
          ? backdrops.first as String?
          : null,
      userData: json['UserData'] is Map<String, dynamic>
          ? UserData.fromJson(json['UserData'] as Map<String, dynamic>)
          : null,
      artists: people
          .map(PersonCredit.fromJson)
          .where((person) => person.name.isNotEmpty)
          .toList(growable: false),
      originalLanguage: parseOriginalLanguageFromItemJson(json),
    );
  }
}
