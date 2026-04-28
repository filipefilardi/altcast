/// Persisted record for one offline-available video. Kept minimal — enough
/// to render in the downloads list and to substitute for a Jellyfin stream
/// URL in the player.
class DownloadedItem {
  const DownloadedItem({
    required this.id,
    required this.name,
    required this.filePath,
    this.year,
    this.runTimeTicks,
    this.imageTag,
    this.serverItemId,
  });

  /// The Jellyfin item id this download corresponds to.
  final String id;
  final String name;

  /// Absolute path on disk to the downloaded video file.
  final String filePath;

  final int? year;
  final int? runTimeTicks;
  final String? imageTag;

  /// Defensive duplicate of [id] — kept for forward compat if we ever
  /// rename the manifest's primary key.
  final String? serverItemId;

  Duration? get runTime => runTimeTicks == null
      ? null
      : Duration(microseconds: runTimeTicks! ~/ 10);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filePath': filePath,
        if (year != null) 'year': year,
        if (runTimeTicks != null) 'runTimeTicks': runTimeTicks,
        if (imageTag != null) 'imageTag': imageTag,
        if (serverItemId != null) 'serverItemId': serverItemId,
      };

  factory DownloadedItem.fromJson(Map<String, dynamic> json) {
    return DownloadedItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      filePath: json['filePath'] as String,
      year: json['year'] as int?,
      runTimeTicks: json['runTimeTicks'] as int?,
      imageTag: json['imageTag'] as String?,
      serverItemId: json['serverItemId'] as String?,
    );
  }
}
