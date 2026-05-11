class TrickplayManifest {
  const TrickplayManifest({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.intervalMs,
  });

  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final int intervalMs;

  int get thumbnailsPerTile => tileWidth * tileHeight;

  int get tileCount {
    final perTile = thumbnailsPerTile;
    if (perTile <= 0) return 0;
    return (thumbnailCount / perTile).ceil();
  }
}

class OfflineTrickplayData {
  const OfflineTrickplayData({
    required this.manifest,
    required this.tileFilesByIndex,
  });

  final TrickplayManifest manifest;
  final Map<int, String> tileFilesByIndex;

  Map<String, dynamic> toJson() => {
    'manifest': {
      'width': manifest.width,
      'height': manifest.height,
      'tileWidth': manifest.tileWidth,
      'tileHeight': manifest.tileHeight,
      'thumbnailCount': manifest.thumbnailCount,
      'intervalMs': manifest.intervalMs,
    },
    'tileFilesByIndex': {
      for (final e in tileFilesByIndex.entries) '${e.key}': e.value,
    },
  };

  factory OfflineTrickplayData.fromJson(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json['manifest'] as Map);
    final files = Map<String, dynamic>.from(json['tileFilesByIndex'] as Map);
    return OfflineTrickplayData(
      manifest: TrickplayManifest(
        width: m['width'] as int,
        height: m['height'] as int,
        tileWidth: m['tileWidth'] as int,
        tileHeight: m['tileHeight'] as int,
        thumbnailCount: m['thumbnailCount'] as int,
        intervalMs: m['intervalMs'] as int,
      ),
      tileFilesByIndex: {
        for (final e in files.entries) int.parse(e.key): e.value as String,
      },
    );
  }
}

class TrickplayFrame {
  const TrickplayFrame({
    required this.urls,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.tileX,
    required this.tileY,
  });

  final List<String> urls;
  final int thumbWidth;
  final int thumbHeight;
  final int tileX;
  final int tileY;
}
