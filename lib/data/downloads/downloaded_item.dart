import '../jellyfin/models/trickplay.dart';

enum DownloadedItemKind { movie, episode }

DownloadedItemKind _kindFromName(String? raw) {
  return raw == 'episode'
      ? DownloadedItemKind.episode
      : DownloadedItemKind.movie;
}

/// Persisted record for one offline-available video. Kept minimal — enough
/// to render in the downloads list and to substitute for a Jellyfin stream
/// URL in the player.
class DownloadedItem {
  const DownloadedItem({
    required this.id,
    required this.name,
    required this.filePath,
    this.kind = DownloadedItemKind.movie,
    this.year,
    this.runTimeTicks,
    this.imageTag,
    this.serverItemId,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.introStartTicks,
    this.introEndTicks,
    this.creditsStartTicks,
    this.creditsEndTicks,
    this.externalSubtitles = const [],
    this.offlineTrickplay,
  });

  /// The Jellyfin item id this download corresponds to.
  final String id;
  final String name;

  /// Absolute path on disk to the downloaded video file.
  final String filePath;

  /// Movie or episode — drives how the row renders in the downloads list.
  final DownloadedItemKind kind;

  final int? year;
  final int? runTimeTicks;
  final String? imageTag;

  /// Defensive duplicate of [id] — kept for forward compat if we ever
  /// rename the manifest's primary key.
  final String? serverItemId;

  // Episode-only metadata. Movies leave these null.
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? introStartTicks;
  final int? introEndTicks;
  final int? creditsStartTicks;
  final int? creditsEndTicks;
  final List<DownloadedExternalSubtitle> externalSubtitles;
  final OfflineTrickplayData? offlineTrickplay;

  Duration? get runTime =>
      runTimeTicks == null ? null : Duration(microseconds: runTimeTicks! ~/ 10);

  /// "S01·E03" style label for an episode, or null for movies.
  String? get episodeLabel {
    if (kind != DownloadedItemKind.episode) return null;
    if (seasonNumber == null || episodeNumber == null) return null;
    final ep = episodeNumber!.toString().padLeft(2, '0');
    return 'S$seasonNumber·E$ep';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'kind': kind.name,
    if (year != null) 'year': year,
    if (runTimeTicks != null) 'runTimeTicks': runTimeTicks,
    if (imageTag != null) 'imageTag': imageTag,
    if (serverItemId != null) 'serverItemId': serverItemId,
    if (seriesId != null) 'seriesId': seriesId,
    if (seriesName != null) 'seriesName': seriesName,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
    if (introStartTicks != null) 'introStartTicks': introStartTicks,
    if (introEndTicks != null) 'introEndTicks': introEndTicks,
    if (creditsStartTicks != null) 'creditsStartTicks': creditsStartTicks,
    if (creditsEndTicks != null) 'creditsEndTicks': creditsEndTicks,
    if (externalSubtitles.isNotEmpty)
      'externalSubtitles': externalSubtitles.map((s) => s.toJson()).toList(),
    if (offlineTrickplay != null) 'offlineTrickplay': offlineTrickplay!.toJson(),
  };

  factory DownloadedItem.fromJson(Map<String, dynamic> json) {
    return DownloadedItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      filePath: json['filePath'] as String,
      kind: _kindFromName(json['kind'] as String?),
      year: json['year'] as int?,
      runTimeTicks: json['runTimeTicks'] as int?,
      imageTag: json['imageTag'] as String?,
      serverItemId: json['serverItemId'] as String?,
      seriesId: json['seriesId'] as String?,
      seriesName: json['seriesName'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      introStartTicks: json['introStartTicks'] as int?,
      introEndTicks: json['introEndTicks'] as int?,
      creditsStartTicks: json['creditsStartTicks'] as int?,
      creditsEndTicks: json['creditsEndTicks'] as int?,
      externalSubtitles: ((json['externalSubtitles'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DownloadedExternalSubtitle.fromJson)
          .toList(growable: false),
      offlineTrickplay: json['offlineTrickplay'] is Map
          ? OfflineTrickplayData.fromJson(
              Map<String, dynamic>.from(json['offlineTrickplay'] as Map),
            )
          : null,
    );
  }
}

class DownloadedExternalSubtitle {
  const DownloadedExternalSubtitle({
    required this.id,
    required this.filePath,
    this.streamIndex,
    this.title,
    this.language,
    this.codec,
  });

  final String id;
  final String filePath;
  final int? streamIndex;
  final String? title;
  final String? language;
  final String? codec;

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    if (streamIndex != null) 'streamIndex': streamIndex,
    if (title != null) 'title': title,
    if (language != null) 'language': language,
    if (codec != null) 'codec': codec,
  };

  factory DownloadedExternalSubtitle.fromJson(Map<String, dynamic> json) {
    return DownloadedExternalSubtitle(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      streamIndex: json['streamIndex'] as int?,
      title: json['title'] as String?,
      language: json['language'] as String?,
      codec: json['codec'] as String?,
    );
  }
}

/// Live state for a download that's queued or in flight. Carries the same
/// display info as [DownloadedItem] so the downloads screen can render it
/// the same way before the file lands on disk.
class DownloadProgress {
  const DownloadProgress({
    required this.itemId,
    required this.name,
    required this.fraction,
    this.downloadedBytes,
    this.totalBytes,
    this.kind = DownloadedItemKind.movie,
    this.imageTag,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String itemId;
  final String name;

  /// 0..1; values < 0 mean "indeterminate".
  final double fraction;
  final int? downloadedBytes;
  final int? totalBytes;

  final DownloadedItemKind kind;
  final String? imageTag;

  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  String? get episodeLabel {
    if (kind != DownloadedItemKind.episode) return null;
    if (seasonNumber == null || episodeNumber == null) return null;
    final ep = episodeNumber!.toString().padLeft(2, '0');
    return 'S$seasonNumber·E$ep';
  }

  DownloadProgress copyWithFraction(double f) => DownloadProgress(
    itemId: itemId,
    name: name,
    fraction: f,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    kind: kind,
    imageTag: imageTag,
    seriesId: seriesId,
    seriesName: seriesName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );

  DownloadProgress copyWithBytes({
    required int downloaded,
    required int? total,
  }) => DownloadProgress(
    itemId: itemId,
    name: name,
    fraction: total != null && total > 0 ? downloaded / total : fraction,
    downloadedBytes: downloaded,
    totalBytes: total,
    kind: kind,
    imageTag: imageTag,
    seriesId: seriesId,
    seriesName: seriesName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
}

/// Visible failed-download state. Kept separate from [DownloadProgress] so the
/// downloads screen can offer retry/dismiss actions instead of making failed
/// queue entries disappear.
class DownloadFailure {
  const DownloadFailure({
    required this.itemId,
    required this.name,
    required this.message,
    this.kind = DownloadedItemKind.movie,
    this.year,
    this.runTimeTicks,
    this.imageTag,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String itemId;
  final String name;
  final String message;
  final DownloadedItemKind kind;
  final int? year;
  final int? runTimeTicks;
  final String? imageTag;
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  String? get episodeLabel {
    if (kind != DownloadedItemKind.episode) return null;
    if (seasonNumber == null || episodeNumber == null) return null;
    final ep = episodeNumber!.toString().padLeft(2, '0');
    return 'S$seasonNumber·E$ep';
  }
}
