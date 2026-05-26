part of '../player_material_theme.dart';

class AltCastTrickplayPreviewBubble extends StatelessWidget {
  const AltCastTrickplayPreviewBubble({
    super.key,
    required this.session,
    required this.position,
    required this.totalDuration,
    required this.alignPercent,
    this.tokens = kDefaultPlayerMaterialTokens,
  });

  final TrickplaySession session;
  final Duration position;
  final Duration totalDuration;
  final double alignPercent;
  final PlayerMaterialTokens tokens;

  @override
  Widget build(BuildContext context) {
    final frame = session.frameAtWithDuration(
      position,
      totalDuration: totalDuration,
    );
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTabletOrDesktop = shortestSide >= tokens.previewTabletBreakpoint;
    final safeThumbWidth = frame.thumbWidth <= 0
        ? tokens.previewFallbackThumbWidth
        : frame.thumbWidth.toDouble();
    final safeThumbHeight = frame.thumbHeight <= 0
        ? tokens.previewFallbackThumbHeight
        : frame.thumbHeight.toDouble();
    final thumbAspect = safeThumbWidth / safeThumbHeight;
    final preferredWidth = isTabletOrDesktop
        ? tokens.previewWidthLarge
        : tokens.previewWidthSmall;
    final minHeight = isTabletOrDesktop
        ? tokens.previewMinHeightLarge
        : tokens.previewMinHeightSmall;
    final maxHeight = isTabletOrDesktop
        ? tokens.previewMaxHeightLarge
        : tokens.previewMaxHeightSmall;
    var frameWidth = preferredWidth;
    var frameHeight = frameWidth / thumbAspect;
    if (frameHeight > maxHeight) {
      frameHeight = maxHeight;
      frameWidth = frameHeight * thumbAspect;
    } else if (frameHeight < minHeight) {
      frameHeight = minHeight;
      frameWidth = frameHeight * thumbAspect;
    }
    final tileColumns = session.manifest.tileWidth;
    final tileRows = session.manifest.tileHeight;
    final tileImageWidth = frameWidth * tileColumns;
    final safeTileRows = tileRows.clamp(1, tokens.previewTileRowsMax);
    final tileImageHeight = frameHeight * safeTileRows;
    final xOffset = frame.tileX * frameWidth;
    final yOffset = frame.tileY * frameHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final left = ((constraints.maxWidth - frameWidth) * alignPercent).clamp(
          0.0,
          (constraints.maxWidth - frameWidth).clamp(0.0, double.infinity),
        );
        return SizedBox(
          height: frameHeight + tokens.previewCaptionHeight,
          child: Stack(
            children: [
              Positioned(
                left: left,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    tokens.previewBorderRadius,
                  ),
                  child: SizedBox(
                    width: frameWidth,
                    height: frameHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: Colors.black.withValues(
                            alpha: tokens.previewFrameBackgroundAlpha,
                          ),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: tileImageWidth,
                              maxWidth: tileImageWidth,
                              minHeight: tileImageHeight,
                              maxHeight: tileImageHeight,
                              child: Transform.translate(
                                offset: Offset(-xOffset, -yOffset),
                                child: SizedBox(
                                  width: tileImageWidth,
                                  height: tileImageHeight,
                                  child: _FallbackNetworkImage(
                                    urls: frame.urls,
                                    width: tileImageWidth,
                                    height: tileImageHeight,
                                    tokens: tokens,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: tokens.previewCaptionPaddingH,
                              vertical: tokens.previewCaptionPaddingV,
                            ),
                            color: Colors.black.withValues(
                              alpha: tokens.previewCaptionBackgroundAlpha,
                            ),
                            child: Text(
                              _formatPlayerTimestamp(position),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isTabletOrDesktop
                                    ? tokens.previewCaptionFontSizeLarge
                                    : tokens.previewCaptionFontSizeSmall,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FallbackNetworkImage extends ConsumerStatefulWidget {
  const _FallbackNetworkImage({
    required this.urls,
    required this.width,
    required this.height,
    required this.tokens,
  });

  final List<String> urls;
  final double width;
  final double height;
  final PlayerMaterialTokens tokens;

  @override
  ConsumerState<_FallbackNetworkImage> createState() =>
      _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends ConsumerState<_FallbackNetworkImage> {
  late Future<Uint8List?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _FallbackNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List?> _loadBytes() async {
    final dio = ref.read(jellyfinApiProvider).dio;
    for (final url in widget.urls) {
      try {
        final data = await _TrickplayTileCache.getOrFetch(dio, url);
        if (data != null && data.isNotEmpty) {
          if (_trickplayDebugLogs) {
            debugPrintSynchronously(
              'Trickplay image loaded from cache/network url=$url bytes=${data.length}',
            );
          }
          return data;
        }
        if (_trickplayDebugLogs) {
          debugPrintSynchronously('Trickplay image empty payload url=$url');
        }
      } catch (e) {
        if (_trickplayDebugLogs) {
          debugPrintSynchronously('Trickplay image failed error=$e url=$url');
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: widget.tokens.previewLoadingSpinnerSize,
              height: widget.tokens.previewLoadingSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: widget.tokens.previewLoadingSpinnerStrokeWidth,
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      },
    );
  }
}
