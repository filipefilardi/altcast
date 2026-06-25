enum SeerrMediaType { movie, tv, person, unknown }

SeerrMediaType seerrMediaTypeFromJson(String? value) {
  switch (value) {
    case 'movie':
      return SeerrMediaType.movie;
    case 'tv':
      return SeerrMediaType.tv;
    case 'person':
      return SeerrMediaType.person;
    default:
      return SeerrMediaType.unknown;
  }
}

extension SeerrMediaTypeLabel on SeerrMediaType {
  String get apiValue => switch (this) {
    SeerrMediaType.movie => 'movie',
    SeerrMediaType.tv => 'tv',
    SeerrMediaType.person => 'person',
    SeerrMediaType.unknown => 'all',
  };

  String get label => switch (this) {
    SeerrMediaType.movie => 'Movie',
    SeerrMediaType.tv => 'TV Show',
    SeerrMediaType.person => 'Person',
    SeerrMediaType.unknown => 'Media',
  };
}

enum SeerrMediaStatus {
  unknown,
  pending,
  processing,
  partiallyAvailable,
  available,
  deleted,
}

SeerrMediaStatus seerrMediaStatusFromJson(Object? value) {
  final status = value is num ? value.toInt() : int.tryParse('$value');
  return switch (status) {
    2 => SeerrMediaStatus.pending,
    3 => SeerrMediaStatus.processing,
    4 => SeerrMediaStatus.partiallyAvailable,
    5 => SeerrMediaStatus.available,
    6 => SeerrMediaStatus.deleted,
    _ => SeerrMediaStatus.unknown,
  };
}

enum SeerrRequestStatus {
  unknown,
  pending,
  approved,
  declined,
  failed,
  completed,
}

SeerrRequestStatus seerrRequestStatusFromJson(Object? value) {
  final status = value is num ? value.toInt() : int.tryParse('$value');
  return switch (status) {
    1 => SeerrRequestStatus.pending,
    2 => SeerrRequestStatus.approved,
    3 => SeerrRequestStatus.declined,
    4 => SeerrRequestStatus.failed,
    5 => SeerrRequestStatus.completed,
    _ => SeerrRequestStatus.unknown,
  };
}

extension SeerrRequestStatusLabel on SeerrRequestStatus {
  String get label => switch (this) {
    SeerrRequestStatus.pending => 'Pending',
    SeerrRequestStatus.approved => 'Approved',
    SeerrRequestStatus.declined => 'Declined',
    SeerrRequestStatus.failed => 'Failed',
    SeerrRequestStatus.completed => 'Completed',
    SeerrRequestStatus.unknown => 'Requested',
  };
}

class SeerrSession {
  const SeerrSession({
    required this.serverUrl,
    required this.cookieHeader,
    required this.username,
  });

  final String serverUrl;
  final String cookieHeader;
  final String username;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'cookieHeader': cookieHeader,
    'username': username,
  };

  factory SeerrSession.fromJson(Map<String, dynamic> json) {
    return SeerrSession(
      serverUrl: json['serverUrl'] as String? ?? '',
      cookieHeader: json['cookieHeader'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }

  bool get isValid => serverUrl.isNotEmpty && cookieHeader.isNotEmpty;
}

class SeerrPagedResult<T> {
  const SeerrPagedResult({
    required this.results,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<T> results;
  final int page;
  final int totalPages;
  final int totalResults;
}

class SeerrMediaInfo {
  const SeerrMediaInfo({
    required this.status,
    required this.requests,
    this.tmdbId,
    this.tvdbId,
    this.jellyfinMediaId,
    this.jellyfinMediaId4k,
  });

  final int? tmdbId;
  final int? tvdbId;
  final String? jellyfinMediaId;
  final String? jellyfinMediaId4k;
  final SeerrMediaStatus status;
  final List<SeerrMediaRequestSummary> requests;

  factory SeerrMediaInfo.fromJson(Map<String, dynamic> json) {
    return SeerrMediaInfo(
      tmdbId: _intFromJson(json['tmdbId']),
      tvdbId: _intFromJson(json['tvdbId']),
      jellyfinMediaId: json['jellyfinMediaId'] as String?,
      jellyfinMediaId4k: json['jellyfinMediaId4k'] as String?,
      status: seerrMediaStatusFromJson(json['status']),
      requests: ((json['requests'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SeerrMediaRequestSummary.fromJson(_stringMap(item)))
          .toList(growable: false),
    );
  }

  SeerrRequestStatus? get latestRequestStatus {
    if (requests.isEmpty) return null;
    return requests.last.status;
  }
}

class SeerrMediaRequestSummary {
  const SeerrMediaRequestSummary({required this.id, required this.status});

  final int? id;
  final SeerrRequestStatus status;

  factory SeerrMediaRequestSummary.fromJson(Map<String, dynamic> json) {
    return SeerrMediaRequestSummary(
      id: _intFromJson(json['id']),
      status: seerrRequestStatusFromJson(json['status']),
    );
  }
}

class SeerrMediaItem {
  const SeerrMediaItem({
    required this.id,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.mediaInfo,
  });

  final int id;
  final SeerrMediaType mediaType;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final SeerrMediaInfo? mediaInfo;

  int? get year {
    final raw = releaseDate?.trim();
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }

  String? get posterUrl =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/w342$posterPath';

  String? get backdropUrl => backdropPath == null
      ? null
      : 'https://image.tmdb.org/t/p/w780$backdropPath';

  String? get jellyfinItemId =>
      mediaInfo?.jellyfinMediaId ?? mediaInfo?.jellyfinMediaId4k;

  bool get canOpenInLibrary =>
      jellyfinItemId != null &&
      mediaInfo?.status == SeerrMediaStatus.available &&
      (mediaType == SeerrMediaType.movie || mediaType == SeerrMediaType.tv);

  String get statusLabel {
    if (mediaInfo?.status == SeerrMediaStatus.available) return 'Available';
    if (mediaInfo?.status == SeerrMediaStatus.processing) return 'Processing';
    if (mediaInfo?.status == SeerrMediaStatus.partiallyAvailable) {
      return 'Partial';
    }
    final request = mediaInfo?.latestRequestStatus;
    if (request != null) return request.label;
    return 'Request';
  }

  bool get canRequest {
    final mediaStatus = mediaInfo?.status;
    if (mediaStatus == SeerrMediaStatus.available ||
        mediaStatus == SeerrMediaStatus.processing ||
        mediaStatus == SeerrMediaStatus.partiallyAvailable) {
      return false;
    }
    final requestStatus = mediaInfo?.latestRequestStatus;
    return requestStatus == null ||
        requestStatus == SeerrRequestStatus.declined ||
        requestStatus == SeerrRequestStatus.failed;
  }

  factory SeerrMediaItem.fromJson(Map<String, dynamic> json) {
    final mediaType = seerrMediaTypeFromJson(json['mediaType'] as String?);
    final title =
        json['title'] as String? ??
        json['name'] as String? ??
        json['originalTitle'] as String? ??
        json['originalName'] as String? ??
        'Untitled';
    return SeerrMediaItem(
      id: _intFromJson(json['id']) ?? 0,
      mediaType: mediaType,
      title: title,
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      releaseDate:
          json['releaseDate'] as String? ?? json['firstAirDate'] as String?,
      mediaInfo: json['mediaInfo'] is Map
          ? SeerrMediaInfo.fromJson(_stringMap(json['mediaInfo'] as Map))
          : null,
    );
  }
}

class SeerrSeason {
  const SeerrSeason({
    required this.seasonNumber,
    required this.name,
    this.episodeCount,
  });

  final int seasonNumber;
  final String name;
  final int? episodeCount;

  factory SeerrSeason.fromJson(Map<String, dynamic> json) {
    final number = _intFromJson(json['seasonNumber']) ?? 0;
    return SeerrSeason(
      seasonNumber: number,
      name: json['name'] as String? ?? 'Season $number',
      episodeCount: _intFromJson(json['episodeCount']),
    );
  }
}

class SeerrMediaDetails extends SeerrMediaItem {
  const SeerrMediaDetails({
    required super.id,
    required super.mediaType,
    required super.title,
    super.overview,
    super.posterPath,
    super.backdropPath,
    super.releaseDate,
    super.mediaInfo,
    this.seasons = const [],
    this.runtime,
  });

  final List<SeerrSeason> seasons;
  final int? runtime;

  factory SeerrMediaDetails.fromJson(
    Map<String, dynamic> json,
    SeerrMediaType fallbackType,
  ) {
    final base = SeerrMediaItem.fromJson({
      ...json,
      'mediaType': json['mediaType'] ?? fallbackType.apiValue,
    });
    return SeerrMediaDetails(
      id: base.id,
      mediaType: base.mediaType,
      title: base.title,
      overview: base.overview,
      posterPath: base.posterPath,
      backdropPath: base.backdropPath,
      releaseDate: base.releaseDate,
      mediaInfo: base.mediaInfo,
      runtime: _intFromJson(json['runtime']),
      seasons: ((json['seasons'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SeerrSeason.fromJson(_stringMap(item)))
          .where((season) => season.seasonNumber > 0)
          .toList(growable: false),
    );
  }
}

class SeerrRequest {
  const SeerrRequest({
    required this.id,
    required this.mediaType,
    required this.status,
    this.mediaStatus = SeerrMediaStatus.unknown,
    this.tmdbId,
    this.title,
    this.posterPath,
    this.backdropPath,
    this.requestedByName,
    this.jellyfinItemId,
    this.downloads = const [],
    this.createdAt,
    this.updatedAt,
    this.seasons = const [],
  });

  final int id;
  final SeerrMediaType mediaType;
  final SeerrRequestStatus status;
  final SeerrMediaStatus mediaStatus;
  final int? tmdbId;
  final String? title;
  final String? posterPath;
  final String? backdropPath;
  final String? requestedByName;
  final String? jellyfinItemId;
  final List<SeerrDownloadStatus> downloads;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<int> seasons;

  String get statusLabel {
    if (status == SeerrRequestStatus.failed) return status.label;
    if (status == SeerrRequestStatus.declined) return status.label;
    if (status == SeerrRequestStatus.pending) return status.label;
    if (mediaStatus == SeerrMediaStatus.available) return 'Available';
    if (mediaStatus == SeerrMediaStatus.processing) return 'Processing';
    if (mediaStatus == SeerrMediaStatus.partiallyAvailable) return 'Partial';
    return status.label;
  }

  bool get canRetry => status == SeerrRequestStatus.failed;
  bool get canOpenInLibrary =>
      jellyfinItemId != null &&
      (mediaStatus == SeerrMediaStatus.available ||
          status == SeerrRequestStatus.completed);

  double? get progress {
    if (status == SeerrRequestStatus.pending) return 0;
    if (mediaStatus == SeerrMediaStatus.available ||
        status == SeerrRequestStatus.completed) {
      return 1;
    }
    if (status == SeerrRequestStatus.failed ||
        status == SeerrRequestStatus.declined) {
      return null;
    }
    if (downloads.isEmpty) return null;
    final totalSize = downloads.fold<int>(0, (sum, item) => sum + item.size);
    final totalLeft = downloads.fold<int>(
      0,
      (sum, item) => sum + item.sizeLeft,
    );
    if (totalSize <= 0) return null;
    return ((totalSize - totalLeft) / totalSize).clamp(0.0, 1.0).toDouble();
  }

  String? get processingDetail {
    if (downloads.isEmpty) return null;
    final first = downloads.first;
    final timeLeft = first.timeLeft.trim();
    final percent = progress == null ? null : '${(progress! * 100).round()}%';
    if (percent != null && timeLeft.isNotEmpty) {
      return '$percent downloaded • ETA $timeLeft';
    }
    if (percent != null) return '$percent downloaded';
    if (timeLeft.isNotEmpty) return 'ETA $timeLeft';
    return null;
  }

  String? get posterUrl =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/w185$posterPath';

  String? get backdropUrl => backdropPath == null
      ? null
      : 'https://image.tmdb.org/t/p/w500$backdropPath';

  SeerrRequest copyWith({
    String? title,
    String? posterPath,
    String? backdropPath,
    String? requestedByName,
    String? jellyfinItemId,
    List<SeerrDownloadStatus>? downloads,
  }) {
    return SeerrRequest(
      id: id,
      mediaType: mediaType,
      status: status,
      mediaStatus: mediaStatus,
      tmdbId: tmdbId,
      title: title ?? this.title,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      requestedByName: requestedByName ?? this.requestedByName,
      jellyfinItemId: jellyfinItemId ?? this.jellyfinItemId,
      downloads: downloads ?? this.downloads,
      createdAt: createdAt,
      updatedAt: updatedAt,
      seasons: seasons,
    );
  }

  factory SeerrRequest.fromJson(Map<String, dynamic> json) {
    final media = json['media'] is Map
        ? _stringMap(json['media'] as Map)
        : null;
    final requestedBy = json['requestedBy'] is Map
        ? _stringMap(json['requestedBy'] as Map)
        : null;
    final is4k = json['is4k'] == true;
    final tmdbId = _intFromJson(media?['tmdbId']);
    final jellyfinItemId = media == null
        ? null
        : (is4k ? media['jellyfinMediaId4k'] : media['jellyfinMediaId'])
              as String?;
    final downloadStatus = media == null
        ? null
        : (is4k ? media['downloadStatus4k'] : media['downloadStatus']) as List?;
    return SeerrRequest(
      id: _intFromJson(json['id']) ?? 0,
      mediaType: seerrMediaTypeFromJson(json['type'] as String?),
      status: seerrRequestStatusFromJson(json['status']),
      mediaStatus: seerrMediaStatusFromJson(
        is4k ? (media?['status4k']) : (media?['status']),
      ),
      tmdbId: tmdbId,
      title:
          media?['title'] as String? ??
          media?['name'] as String? ??
          (tmdbId == null ? null : 'TMDb #$tmdbId'),
      posterPath: media?['posterPath'] as String?,
      backdropPath: media?['backdropPath'] as String?,
      requestedByName:
          requestedBy?['displayName'] as String? ??
          requestedBy?['username'] as String? ??
          requestedBy?['jellyfinUsername'] as String? ??
          requestedBy?['plexUsername'] as String? ??
          requestedBy?['email'] as String?,
      jellyfinItemId: jellyfinItemId,
      downloads: (downloadStatus ?? const [])
          .whereType<Map>()
          .map((item) => SeerrDownloadStatus.fromJson(_stringMap(item)))
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      seasons: ((json['seasons'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => _intFromJson(item['seasonNumber']))
          .whereType<int>()
          .toList(growable: false),
    );
  }
}

class SeerrDownloadStatus {
  const SeerrDownloadStatus({
    required this.size,
    required this.sizeLeft,
    required this.status,
    required this.timeLeft,
    required this.title,
  });

  final int size;
  final int sizeLeft;
  final String status;
  final String timeLeft;
  final String title;

  factory SeerrDownloadStatus.fromJson(Map<String, dynamic> json) {
    return SeerrDownloadStatus(
      size: _intFromJson(json['size']) ?? 0,
      sizeLeft: _intFromJson(json['sizeLeft'] ?? json['sizeleft']) ?? 0,
      status: json['status'] as String? ?? '',
      timeLeft:
          json['timeLeft'] as String? ?? json['timeleft'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}

int? _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, dynamic> _stringMap(Map value) => Map<String, dynamic>.from(value);
