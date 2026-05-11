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
