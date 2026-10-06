/// Resolves Jellyfin ticks (100 ns) for the initial playback position.
/// Explicit starts win; ordinary resume prefers progress saved offline.
Duration resolvePlaybackResumePosition({
  int? startTicks,
  int? resumeTicks,
  int? localTicks,
}) {
  final ticks =
      startTicks ??
      (resumeTicks != null && resumeTicks <= 0
          ? 0
          : localTicks ?? resumeTicks ?? 0);
  return ticks <= 0 ? Duration.zero : Duration(microseconds: ticks ~/ 10);
}
