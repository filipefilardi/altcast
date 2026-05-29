part of '../player_material_theme.dart';

class AltCastTrickplaySeekGroup extends ConsumerStatefulWidget {
  const AltCastTrickplaySeekGroup({
    super.key,
    required this.itemId,
    required this.sourceListenable,
    required this.trickplayOverlayNotifier,
    this.tokens = kDefaultPlayerMaterialTokens,
  });

  final String itemId;
  final ValueListenable<StreamSource?> sourceListenable;
  final ValueNotifier<TrickplayOverlayData?> trickplayOverlayNotifier;
  final PlayerMaterialTokens tokens;

  @override
  ConsumerState<AltCastTrickplaySeekGroup> createState() =>
      _AltCastTrickplaySeekGroupState();
}

class _AltCastTrickplaySeekGroupState
    extends ConsumerState<AltCastTrickplaySeekGroup> {
  TrickplaySession? _trickplay;
  Object? _lastManifestKey;
  bool _isScrubbing = false;
  double _scrubPercent = 0.0;
  double? _hoverPercent;

  @override
  void initState() {
    super.initState();
    widget.sourceListenable.addListener(_loadTrickplay);
    unawaited(_loadTrickplay());
  }

  @override
  void dispose() {
    widget.trickplayOverlayNotifier.value = null;
    widget.sourceListenable.removeListener(_loadTrickplay);
    super.dispose();
  }

  Future<void> _loadTrickplay() async {
    final source = widget.sourceListenable.value;
    final key = '${widget.itemId}::${source?.mediaSourceId ?? ''}';
    if (key == _lastManifestKey) return;
    _lastManifestKey = key;
    try {
      TrickplaySession? session;
      final localUrl = source?.url ?? '';
      final isLocal = localUrl.startsWith('file://');
      if (isLocal) {
        final localItem = ref
            .read(downloadManagerProvider)
            .items[widget.itemId];
        final offline = localItem?.offlineTrickplay;
        if (offline != null && offline.tileFilesByIndex.isNotEmpty) {
          session = TrickplaySession.offline(
            itemId: widget.itemId,
            manifest: offline.manifest,
            tileFilesByIndex: offline.tileFilesByIndex,
          );
        } else {
          // Local/offline playback without persisted trickplay tiles:
          // don't attempt remote lookup for a local source.
          session = null;
        }
      } else {
        session = await ref
            .read(jellyfinRepositoryProvider)
            .getTrickplaySession(
              widget.itemId,
              mediaSourceId: source?.mediaSourceId,
            );
      }
      if (!mounted || _lastManifestKey != key) return;
      setState(() => _trickplay = session);
      if (session != null) {
        final dio = ref.read(jellyfinApiProvider).dio;
        final first = session.frameAtWithDuration(Duration.zero);
        unawaited(_TrickplayTileCache.prefetch(dio, first.urls));
      }
    } catch (e) {
      if (_trickplayDebugLogs) {
        debugPrint('Trickplay load failed in controls key=$key error=$e');
      }
      if (!mounted || _lastManifestKey != key) return;
      setState(() => _trickplay = null);
    }
  }

  void _prefetchAround(
    TrickplaySession session,
    Duration position,
    Duration totalDuration,
  ) {
    final dio = ref.read(jellyfinApiProvider).dio;
    final intervalMs = session.manifest.intervalMs;
    final current = session.frameAtWithDuration(
      position,
      totalDuration: totalDuration,
    );
    final prevPos = Duration(
      milliseconds: (position.inMilliseconds - intervalMs).clamp(
        0,
        totalDuration.inMilliseconds,
      ),
    );
    final nextPos = Duration(
      milliseconds: (position.inMilliseconds + intervalMs).clamp(
        0,
        totalDuration.inMilliseconds,
      ),
    );
    final prev = session.frameAtWithDuration(
      prevPos,
      totalDuration: totalDuration,
    );
    final next = session.frameAtWithDuration(
      nextPos,
      totalDuration: totalDuration,
    );
    final urls = <String>[...current.urls, ...prev.urls, ...next.urls];
    unawaited(_TrickplayTileCache.prefetch(dio, urls));
  }

  @override
  Widget build(BuildContext context) {
    final player = video_ctrl.controller(context).player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durSnap) {
            return StreamBuilder<Duration>(
              stream: player.stream.buffer,
              initialData: player.state.buffer,
              builder: (context, bufferSnap) {
                final position = posSnap.data ?? Duration.zero;
                final duration = durSnap.data ?? Duration.zero;
                final buffer = bufferSnap.data ?? Duration.zero;
                final activePercent = _isScrubbing
                    ? _scrubPercent
                    : (_hoverPercent ?? _percent(position, duration));
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AltCastSeekBar(
                          duration: duration,
                          position: position,
                          buffer: buffer,
                          value: activePercent,
                          tokens: widget.tokens,
                          onScrubStart: (percent) {
                            setState(() {
                              _isScrubbing = true;
                              _scrubPercent = percent;
                              _hoverPercent = null;
                            });
                            if (_trickplay != null &&
                                duration > Duration.zero) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                          onScrubUpdate: (percent) {
                            if (!_isScrubbing) return;
                            setState(() => _scrubPercent = percent);
                            if (_trickplay != null &&
                                duration > Duration.zero) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                          onScrubEnd: (percent) async {
                            final target = duration * percent;
                            setState(() {
                              _isScrubbing = false;
                              _scrubPercent = percent;
                            });
                            widget.trickplayOverlayNotifier.value = null;
                            unawaited(player.seek(target));
                          },
                          onHoverPreview: (percent) {
                            if (_isScrubbing || duration <= Duration.zero) {
                              return;
                            }
                            if (percent == null) {
                              setState(() => _hoverPercent = null);
                              widget.trickplayOverlayNotifier.value = null;
                              return;
                            }
                            setState(() => _hoverPercent = percent);
                            if (_trickplay != null) {
                              _prefetchAround(
                                _trickplay!,
                                duration * percent,
                                duration,
                              );
                              widget.trickplayOverlayNotifier.value =
                                  TrickplayOverlayData(
                                    session: _trickplay!,
                                    position: duration * percent,
                                    totalDuration: duration,
                                    alignPercent: percent,
                                  );
                            }
                          },
                        ),
                        SizedBox(height: widget.tokens.seekGroupTimestampGap),
                        Row(
                          children: [
                            Text(
                              _formatPlayerTimestamp(duration * activePercent),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Spacer(),
                            Text(
                              _formatPlayerTimestamp(duration),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  double _percent(Duration value, Duration total) {
    if (total <= Duration.zero) return 0.0;
    final p = value.inMilliseconds / total.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }
}

class _AltCastSeekBar extends StatelessWidget {
  const _AltCastSeekBar({
    required this.duration,
    required this.position,
    required this.buffer,
    required this.value,
    required this.tokens,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onHoverPreview,
  });

  final Duration duration;
  final Duration position;
  final Duration buffer;
  final double value;
  final PlayerMaterialTokens tokens;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final ValueChanged<double?> onHoverPreview;

  @override
  Widget build(BuildContext context) {
    final inherited = MaterialVideoControlsTheme.maybeOf(context);
    final theme = inherited?.normal ?? kDefaultMaterialVideoControlsThemeData;
    final bufferPercent = duration <= Duration.zero
        ? 0.0
        : (buffer.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final hitTargetHeight = math.max(
      theme.seekBarContainerHeight,
      tokens.seekBarTouchTargetHeight,
    );
    return Container(
      margin: theme.seekBarMargin,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double fromDx(double dx) =>
              (dx / constraints.maxWidth).clamp(0.0, 1.0);

          return MouseRegion(
            onHover: (e) => onHoverPreview(fromDx(e.localPosition.dx)),
            onExit: (_) => onHoverPreview(null),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (d) =>
                  onScrubStart(fromDx(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  onScrubUpdate(fromDx(d.localPosition.dx)),
              onHorizontalDragEnd: (_) => onScrubEnd(value),
              onHorizontalDragCancel: () => onScrubEnd(value),
              onTapDown: (d) {
                final next = fromDx(d.localPosition.dx);
                onScrubStart(next);
              },
              onTapUp: (_) => onScrubEnd(value),
              onTapCancel: () => onScrubEnd(value),
              child: SizedBox(
                width: constraints.maxWidth,
                height: hitTargetHeight,
                child: Center(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: theme.seekBarContainerHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          width: constraints.maxWidth,
                          height: theme.seekBarHeight,
                          color: theme.seekBarColor,
                          child: Stack(
                            children: [
                              FractionallySizedBox(
                                widthFactor: bufferPercent,
                                child: Container(
                                  color: theme.seekBarBufferColor,
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: value,
                                child: Container(
                                  color: theme.seekBarPositionColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left:
                              (constraints.maxWidth -
                                  theme.seekBarThumbSize / 2) *
                              value,
                          bottom:
                              -(tokens.seekBarThumbSize / 2) +
                              tokens.seekBarHeight / 2,
                          child: Container(
                            width: theme.seekBarThumbSize,
                            height: theme.seekBarThumbSize,
                            decoration: BoxDecoration(
                              color: theme.seekBarThumbColor,
                              borderRadius: BorderRadius.circular(
                                theme.seekBarThumbSize / 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
