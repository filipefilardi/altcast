import 'browse_item.dart';

class Episode {
  const Episode({
    required this.id,
    required this.name,
    required this.seriesId,
    this.seasonId,
    this.overview,
    this.indexNumber,
    this.parentIndexNumber,
    this.runTime,
    this.imageTag,
    this.userData,
  });

  final String id;
  final String name;
  final String seriesId;
  final String? seasonId;
  final String? overview;

  /// Episode number within the season (1-based).
  final int? indexNumber;

  /// Season number this episode belongs to.
  final int? parentIndexNumber;

  final Duration? runTime;
  final String? imageTag;
  final UserData? userData;

  String get shortLabel {
    if (parentIndexNumber == null || indexNumber == null) return '';
    final ep = indexNumber!.toString().padLeft(2, '0');
    return 'S$parentIndexNumber · E$ep';
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final tags = json['ImageTags'];
    return Episode(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Episode',
      seriesId: json['SeriesId'] as String? ?? '',
      seasonId: json['SeasonId'] as String?,
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
    );
  }
}
