import 'browse_item.dart';

class Series {
  const Series({
    required this.id,
    required this.name,
    this.overview,
    this.year,
    this.endYear,
    this.status,
    this.genres = const [],
    this.communityRating,
    this.officialRating,
    this.imageTag,
    this.backdropTag,
    this.userData,
  });

  final String id;
  final String name;
  final String? overview;
  final int? year;
  final int? endYear;

  /// "Continuing" / "Ended".
  final String? status;
  final List<String> genres;
  final double? communityRating;
  final String? officialRating;
  final String? imageTag;
  final String? backdropTag;
  final UserData? userData;

  String get yearLabel {
    if (year == null) return '';
    if (endYear == null || endYear == year) return '$year';
    return '$year–$endYear';
  }

  factory Series.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
    final backdrops = json['BackdropImageTags'];
    final endDate = json['EndDate'] as String?;
    int? endYear;
    if (endDate != null) {
      endYear = DateTime.tryParse(endDate)?.year;
    }
    return Series(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled',
      overview: json['Overview'] as String?,
      year: json['ProductionYear'] as int?,
      endYear: endYear,
      status: json['Status'] as String?,
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
    );
  }
}

class Season {
  const Season({
    required this.id,
    required this.name,
    this.seriesId,
    this.seriesName,
    this.indexNumber,
    this.imageTag,
    this.episodeCount,
  });

  final String id;
  final String name;
  final String? seriesId;
  final String? seriesName;
  final int? indexNumber;
  final String? imageTag;
  final int? episodeCount;

  factory Season.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
    return Season(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Season',
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      imageTag: (tags is Map && tags['Primary'] is String)
          ? tags['Primary'] as String
          : null,
      episodeCount: json['ChildCount'] as int?,
    );
  }
}
