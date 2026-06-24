import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/navigation.dart';
import 'package:altcast/core/widgets/edge_light_background.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/watch_history_store.dart';
import 'package:altcast/features/auth/auth_controller.dart';
import 'package:altcast/features/year_review/year_review_summary.dart';

class YearReviewScreen extends ConsumerStatefulWidget {
  const YearReviewScreen({super.key});

  @override
  ConsumerState<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends ConsumerState<YearReviewScreen> {
  List<WatchHistoryEntry> _entries = const [];
  int? _selectedYear;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;
  String? _serverName;

  JellyfinSession? get _session {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.session : null;
  }

  List<int> get _years {
    final years =
        _entries
            .map((entry) => entry.watchedAt?.toLocal().year)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) years.add(DateTime.now().year);
    return years;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final year = _selectedYear ?? DateTime.now().year;
    final summary = YearReviewSummary.fromEntries(_entries, year);

    return EdgeLightBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Year in review'),
          leading: BackButton(onPressed: () => context.pop()),
          actions: [
            PopupMenuButton<int>(
              tooltip: 'Choose year',
              initialValue: year,
              onSelected: (value) => setState(() => _selectedYear = value),
              itemBuilder: (_) => [
                for (final value in _years)
                  PopupMenuItem(value: value, child: Text('$value')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$year',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 4),
                    const Icon(PiconsRegular.caretDown, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(onRefresh: _refresh, child: _buildBody(summary)),
      ),
    );
  }

  Future<void> _load() async {
    final session = _session;
    if (session == null) return;
    final cached = await ref.read(watchHistoryStoreProvider).read(session);
    if (!mounted) return;
    setState(() {
      _entries = cached;
      _chooseInitialYear();
      _loading = cached.isEmpty;
    });
    final serverNameFuture = _loadServerName(session);
    await _refresh();
    await serverNameFuture;
  }

  Future<void> _loadServerName(JellyfinSession session) async {
    String? name;
    final authRepo = ref.read(authRepositoryProvider);
    try {
      final info = await authRepo.publicServerInfo(session.serverUrl);
      name = info.serverName?.trim();
    } catch (_) {
      final servers = await authRepo.savedServers();
      final matching = servers.where(
        (server) => server.serverUrl == session.serverUrl,
      );
      if (matching.isNotEmpty) name = matching.first.serverName?.trim();
    }
    if (!mounted) return;
    setState(() {
      _serverName = name == null || name.isEmpty
          ? Uri.tryParse(session.serverUrl)?.host
          : name;
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final session = _session;
    if (session == null) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final live = <BrowseItem>[];
      var startIndex = 0;
      const pageSize = 100;
      while (true) {
        final page = await repo.watchHistory(
          startIndex: startIndex,
          limit: pageSize,
        );
        live.addAll(page.items);
        if (!page.hasMore || page.items.isEmpty) break;
        startIndex += page.fetchedItemCount ?? page.items.length;
      }

      var merged = mergeWatchHistory(_entries, live);
      try {
        final available = await repo.availableItemIds(
          merged.map((entry) => entry.id),
        );
        merged = merged
            .map(
              (entry) =>
                  entry.copyWith(isAvailable: available.contains(entry.id)),
            )
            .toList(growable: false);
      } catch (_) {
        // Keep the last known state instead of inventing deletions when the
        // availability check fails.
      }
      await ref.read(watchHistoryStoreProvider).write(session, merged);
      final reviewYear = _selectedYear ?? DateTime.now().year;
      unawaited(
        _cacheReviewArtwork(
          repo,
          YearReviewSummary.fromEntries(merged, reviewYear),
        ),
      );
      if (!mounted) return;
      setState(() {
        _entries = merged;
        _chooseInitialYear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _cacheReviewArtwork(
    JellyfinRepository repo,
    YearReviewSummary summary,
  ) async {
    final urls = <String>{};
    final topSeries = summary.topSeries;
    if (topSeries != null) {
      final seriesId = topSeries.entries.first.seriesId;
      if (seriesId != null && seriesId.isNotEmpty) {
        urls.add(repo.heroBackdropUrl(seriesId));
      }
    }
    final person = summary.starPower?.person;
    final personImage = repo.personImageUrl(
      person?.id,
      person?.primaryImageTag,
      width: 720,
    );
    if (personImage != null) urls.add(personImage);

    final byTitle = <String, WatchHistoryEntry>{};
    for (final entry in summary.entries) {
      final key = entry.kind == MediaKind.episode
          ? entry.seriesId ?? entry.seriesName ?? entry.id
          : '${entry.kind.name}:${entry.id}';
      byTitle.putIfAbsent(key, () => entry);
    }
    for (final entry in byTitle.values) {
      final seriesId = entry.kind == MediaKind.episode ? entry.seriesId : null;
      final poster = repo.posterUrl(
        entry.id,
        seriesId == null ? entry.imageTag : null,
        seriesId: seriesId,
      );
      if (poster != null) urls.add(poster);
    }
    for (final entry in [summary.firstWatched, summary.lastWatched]) {
      if (entry == null) continue;
      final seriesId = entry.kind == MediaKind.episode ? entry.seriesId : null;
      final poster = repo.posterUrl(
        entry.id,
        seriesId == null ? entry.imageTag : null,
        seriesId: seriesId,
        width: 160,
      );
      if (poster != null) urls.add(poster);
    }

    final cache = DefaultCacheManager();
    for (final url in urls) {
      try {
        await cache.getSingleFile(url);
      } catch (_) {
        // Artwork caching is best-effort; persisted recap data remains usable.
      }
    }
  }

  void _chooseInitialYear() {
    if (_selectedYear != null && _years.contains(_selectedYear)) return;
    final featured = featuredYearReviewYear(DateTime.now());
    _selectedYear = _years.contains(featured) ? featured : _years.first;
  }

  Widget _buildBody(YearReviewSummary summary) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (summary.isEmpty && _error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          ErrorStateView(
            title: "Couldn't build your year in review",
            message: 'Pull to retry or check your server connection.',
            onRetry: _refresh,
          ),
        ],
      );
    }
    if (summary.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.calendarStar,
              title: 'No highlights yet',
              message: 'Finished movies and episodes will shape your recap.',
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        if (_refreshing) const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReviewHero(summary: summary),
                const SizedBox(height: 16),
                _TotalsGrid(summary: summary),
                const SizedBox(height: 16),
                if (summary.topSeries != null)
                  _TopSeriesCard(topSeries: summary.topSeries!),
                if (summary.topSeries != null) const SizedBox(height: 16),
                if (summary.topGenres.isNotEmpty)
                  _TopGenresCard(genres: summary.topGenres),
                if (summary.topGenres.isNotEmpty) const SizedBox(height: 16),
                if (summary.starPower != null)
                  _StarPowerCard(starPower: summary.starPower!),
                if (summary.starPower != null) const SizedBox(height: 16),
                _MonthlyActivityCard(summary: summary),
                const SizedBox(height: 16),
                _FirstLastCard(summary: summary),
                const SizedBox(height: 16),
                _PosterMosaic(year: summary.year, entries: summary.entries),
                const SizedBox(height: 20),
                _ServerFooter(
                  serverName: _serverName ?? 'your Jellyfin server',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Based on synced Jellyfin history. Watch time is estimated from unique completed titles. Rewatches are not included.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "Your saved recap is shown, but it couldn't refresh from Jellyfin.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewHero extends StatefulWidget {
  const _ReviewHero({required this.summary});

  final YearReviewSummary summary;

  @override
  State<_ReviewHero> createState() => _ReviewHeroState();
}

class _ReviewHeroState extends State<_ReviewHero> {
  _WatchTimeUnit _watchTimeUnit = _WatchTimeUnit.hours;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final watchTime = _watchTimeParts(
      summary.estimatedWatchTime,
      unit: _watchTimeUnit,
    );
    final currentYear = DateTime.now().year;
    final title = summary.year == currentYear
        ? 'Your year so far'
        : 'Your ${summary.year} in review';
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.34),
              AppColors.primaryDark.withValues(alpha: 0.15),
              AppColors.surfaceElevated,
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.26),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    PiconsRegular.sparkle,
                    color: AppColors.accent,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${summary.year} VIEWING STORY',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: constraints.maxWidth >= 600 ? 38 : 31,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
                height: 1.02,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'ESTIMATED WATCH TIME',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label:
                  'Toggle estimated watch time between hours, minutes, and days',
              child: InkWell(
                onTap: () => setState(() {
                  final next =
                      (_watchTimeUnit.index + 1) % _WatchTimeUnit.values.length;
                  _watchTimeUnit = _WatchTimeUnit.values[next];
                }),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_watchTimeUnit),
                    tween: Tween(begin: 0, end: watchTime.$1),
                    duration: const Duration(milliseconds: 760),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, _) => Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value.toStringAsFixed(watchTime.$3),
                            style: TextStyle(
                              fontSize: constraints.maxWidth >= 600 ? 68 : 52,
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                              letterSpacing: -2,
                            ),
                          ),
                          TextSpan(
                            text: ' ${watchTime.$2}',
                            style: TextStyle(
                              fontSize: constraints.maxWidth >= 600 ? 28 : 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Tap to switch hours / minutes / days',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.summary});

  final YearReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              width: width,
              value: summary.moviesWatched,
              label: 'Movies',
            ),
            _StatCard(
              width: width,
              value: summary.episodesWatched,
              label: 'Episodes',
            ),
            _StatCard(
              width: width,
              value: summary.uniqueSeries,
              label: 'Series',
            ),
            _StatCard(
              width: width,
              value: summary.totalDaysActive,
              label: 'Days active',
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.value,
    required this.label,
  });

  final double width;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 650),
            builder: (_, animatedValue, _) => Text(
              '$animatedValue',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopSeriesCard extends ConsumerWidget {
  const _TopSeriesCard({required this.topSeries});

  final TopSeriesReview topSeries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = topSeries.entries.first;
    final seriesId = entry.seriesId;
    final repo = ref.watch(jellyfinRepositoryProvider);
    return _ArtworkHighlightCard(
      eyebrow: 'YOUR TOP SERIES',
      title: topSeries.name,
      subtitle:
          '${topSeries.episodeCount} episode${topSeries.episodeCount == 1 ? '' : 's'} watched',
      imageSource: seriesId == null || seriesId.isEmpty
          ? repo.backdropUrl(
              entry.id,
              entry.backdropTag,
              fallbackPrimaryTag: entry.imageTag,
            )
          : repo.heroBackdropUrl(seriesId),
      onTap: seriesId == null || seriesId.isEmpty
          ? null
          : () => context.push('/series/$seriesId'),
    );
  }
}

class _TopGenresCard extends StatefulWidget {
  const _TopGenresCard({required this.genres});

  final List<GenreReview> genres;

  @override
  State<_TopGenresCard> createState() => _TopGenresCardState();
}

class _TopGenresCardState extends State<_TopGenresCard> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final selected = widget.genres[_selected];
    return _ReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOP GENRES', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              '${selected.name} • ${selected.count} titles • ${(selected.percentage * 100).round()}%',
              key: ValueKey(selected.name),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < widget.genres.length; index++) ...[
            Semantics(
              button: true,
              selected: index == _selected,
              label:
                  '${widget.genres[index].name}, ${widget.genres[index].count} titles',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selected = index),
                onHover: (hovered) {
                  if (hovered) setState(() => _selected = index);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          widget.genres[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: index == _selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: ColoredBox(
                            color: AppColors.surfaceHighlight,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 0,
                                end: widget.genres[index].percentage,
                              ),
                              duration: Duration(
                                milliseconds: 500 + index * 100,
                              ),
                              curve: Curves.easeOutCubic,
                              builder: (_, value, _) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: value.clamp(0.04, 1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: index == _selected
                                        ? AppColors.primary
                                        : AppColors.primary.withValues(
                                            alpha: 0.42,
                                          ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
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
          const SizedBox(height: 8),
          const Text(
            'A title can belong to multiple genres.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StarPowerCard extends ConsumerWidget {
  const _StarPowerCard({required this.starPower});

  final StarPowerReview starPower;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = starPower.person;
    final repo = ref.watch(jellyfinRepositoryProvider);
    return _ArtworkHighlightCard(
      eyebrow: 'STAR POWER',
      title: person.name,
      subtitle: _starPowerSubtitle(starPower.entries),
      imageSource: repo.personImageUrl(
        person.id,
        person.primaryImageTag,
        width: 720,
      ),
      imageAlignment: Alignment.topCenter,
      portrait: true,
      onTap: person.id == null || person.id!.isEmpty
          ? null
          : () => context.push('/person/${person.id}'),
    );
  }
}

class _MonthlyActivityCard extends StatefulWidget {
  const _MonthlyActivityCard({required this.summary});

  final YearReviewSummary summary;

  @override
  State<_MonthlyActivityCard> createState() => _MonthlyActivityCardState();
}

class _MonthlyActivityCardState extends State<_MonthlyActivityCard> {
  int? _selectedIndex;
  int? _hoveredIndex;

  static const _monthLabels = [
    'J',
    'F',
    'M',
    'A',
    'M',
    'J',
    'J',
    'A',
    'S',
    'O',
    'N',
    'D',
  ];

  @override
  void didUpdateWidget(covariant _MonthlyActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.year != widget.summary.year) {
      _selectedIndex = null;
      _hoveredIndex = null;
    }
  }

  int get _defaultIndex => (widget.summary.busiestMonth ?? 1) - 1;
  int get _activeIndex => _hoveredIndex ?? _selectedIndex ?? _defaultIndex;

  void _moveSelection(int delta) {
    setState(() {
      _selectedIndex = (_activeIndex + delta).clamp(0, 11);
      _hoveredIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final maxCount = summary.monthlyActivity.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return _ReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR WATCHING RHYTHM',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (summary.busiestMonth != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_monthName(summary.busiestMonth!)} was your biggest month.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 20),
          Focus(
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _moveSelection(-1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _moveSelection(1);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              height: 132,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < 12; index++)
                    Expanded(
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoveredIndex = index),
                        onExit: (_) => setState(() => _hoveredIndex = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        begin: 0,
                                        end:
                                            summary.monthlyActivity[index] /
                                            maxCount,
                                      ),
                                      duration: Duration(
                                        milliseconds: 420 + index * 35,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, heightFactor, child) =>
                                          FractionallySizedBox(
                                            heightFactor: heightFactor,
                                            child: child,
                                          ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        decoration: BoxDecoration(
                                          color: index == _activeIndex
                                              ? AppColors.primary
                                              : AppColors.primary.withValues(
                                                  alpha: 0.34,
                                                ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(5),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _MonthlyActivityCardState._monthLabels[index],
                                  style: TextStyle(
                                    color: index == _activeIndex
                                        ? AppColors.primary
                                        : AppColors.textTertiary,
                                    fontSize: 10,
                                    fontWeight: index == _activeIndex
                                        ? FontWeight.w800
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (summary.busiestWeekday != null &&
              summary.busiestHour != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 10) / 2;
                final month = _monthName(_activeIndex + 1).toUpperCase();
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _RhythmInsight(
                        label: '$month TOTAL',
                        value:
                            '${summary.monthlyActivity[_activeIndex]} watched',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _RhythmInsight(
                        label: '$month MIX',
                        value:
                            '${summary.monthlyMovies[_activeIndex]} movies / ${summary.monthlyEpisodes[_activeIndex]} episodes',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _RhythmInsight(
                        label: 'MOST ACTIVE WEEKDAY',
                        value: _weekdayName(summary.busiestWeekday!),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _RhythmInsight(
                        label: 'COMMON FINISH TIME',
                        value: _hourRange(summary.busiestHour!),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _RhythmInsight extends StatelessWidget {
  const _RhythmInsight({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  value,
                  key: ValueKey(value),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstLastCard extends StatelessWidget {
  const _FirstLastCard({required this.summary});

  final YearReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return _ReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BOOKENDS', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final first = _BookendMiniCard(
                label: 'First watch',
                entry: summary.firstWatched!,
              );
              final latest = _BookendMiniCard(
                label: 'Latest watch',
                entry: summary.lastWatched!,
              );
              if (constraints.maxWidth >= 520) {
                return SizedBox(
                  height: 112,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: first),
                      const SizedBox(width: 12),
                      Expanded(child: latest),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  SizedBox(height: 104, child: first),
                  const SizedBox(height: 10),
                  SizedBox(height: 104, child: latest),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookendMiniCard extends ConsumerWidget {
  const _BookendMiniCard({required this.label, required this.entry});

  final String label;
  final WatchHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final seriesId = entry.kind == MediaKind.episode ? entry.seriesId : null;
    final image = repo.posterUrl(
      entry.id,
      seriesId == null ? entry.imageTag : null,
      seriesId: seriesId,
      width: 160,
    );
    return Material(
      color: AppColors.surfaceHighlight.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.isAvailable
            ? () => openItemDetail(context, entry.toBrowseItem())
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 50,
                  height: 75,
                  child: LocalOrNetworkImage(
                    source: image,
                    errorBuilder: (_) => const ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: Icon(
                        PiconsRegular.filmStrip,
                        color: AppColors.textTertiary,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _entryTitle(entry),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                        color: entry.isAvailable
                            ? null
                            : AppColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      entry.isAvailable && entry.watchedAt != null
                          ? _shortDate(entry.watchedAt!.toLocal())
                          : 'No longer on server',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterMosaic extends ConsumerStatefulWidget {
  const _PosterMosaic({required this.year, required this.entries});

  final int year;
  final List<WatchHistoryEntry> entries;

  @override
  ConsumerState<_PosterMosaic> createState() => _PosterMosaicState();
}

class _PosterMosaicState extends ConsumerState<_PosterMosaic> {
  static const _batchSize = 30;
  int _visibleCount = _batchSize;

  @override
  void didUpdateWidget(covariant _PosterMosaic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year) _visibleCount = _batchSize;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final byTitle = <String, WatchHistoryEntry>{};
    for (final entry in widget.entries) {
      final key = entry.kind == MediaKind.episode
          ? entry.seriesId ?? entry.seriesName ?? entry.id
          : '${entry.kind.name}:${entry.id}';
      final current = byTitle[key];
      if (current == null || (!current.isAvailable && entry.isAvailable)) {
        byTitle[key] = entry;
      }
    }
    final allTitles = byTitle.values.toList(growable: false);
    final titles = allTitles.take(_visibleCount).toList(growable: false);
    final remaining = allTitles.length - titles.length;
    return _ReviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR YEAR',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                '${allTitles.length} TITLES',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth >= 600 ? 10 : 5,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2 / 3,
                ),
                itemCount: titles.length,
                itemBuilder: (_, index) {
                  final entry = titles[index];
                  final title = entry.kind == MediaKind.episode
                      ? entry.seriesName ?? entry.name
                      : entry.name;
                  final seriesId = entry.kind == MediaKind.episode
                      ? entry.seriesId
                      : null;
                  return Semantics(
                    button: entry.isAvailable,
                    label: entry.isAvailable
                        ? 'Open $title'
                        : '$title, no longer on server',
                    child: InkWell(
                      onTap: entry.isAvailable
                          ? () => openItemDetail(context, entry.toBrowseItem())
                          : null,
                      borderRadius: BorderRadius.circular(7),
                      child: Opacity(
                        opacity: entry.isAvailable ? 1 : 0.46,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: ColoredBox(
                            color: AppColors.surfaceHighlight,
                            child: LocalOrNetworkImage(
                              source: repo.posterUrl(
                                entry.id,
                                seriesId == null ? entry.imageTag : null,
                                seriesId: seriesId,
                              ),
                              errorBuilder: (_) => const Center(
                                child: Icon(
                                  PiconsRegular.filmStrip,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (remaining > 0) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _visibleCount = (_visibleCount + _batchSize).clamp(
                    0,
                    allTitles.length,
                  );
                }),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Show ${remaining > _batchSize ? _batchSize : remaining} more',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServerFooter extends StatelessWidget {
  const _ServerFooter({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: Text(
        'Proudly streamed from $serverName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

class _ArtworkHighlightCard extends StatelessWidget {
  const _ArtworkHighlightCard({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.imageSource,
    this.imageAlignment = Alignment.center,
    this.portrait = false,
    this.onTap,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final String? imageSource;
  final Alignment imageAlignment;
  final bool portrait;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (portrait) ...[
                const ColoredBox(color: AppColors.background),
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.42,
                    heightFactor: 1,
                    child: LocalOrNetworkImage(
                      source: imageSource,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_) =>
                          const ColoredBox(color: AppColors.surfaceHighlight),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0, 0.5, 0.74, 1],
                      colors: [
                        AppColors.background,
                        AppColors.background,
                        AppColors.background.withValues(alpha: 0.42),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ] else
                LocalOrNetworkImage(
                  source: imageSource,
                  alignment: imageAlignment,
                  errorBuilder: (_) =>
                      const ColoredBox(color: AppColors.surfaceHighlight),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.5, 0.76, 1],
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.9),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: portrait ? 0.72 : 1,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                eyebrow,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.78,
                                        ),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _entryTitle(WatchHistoryEntry entry) {
  if (entry.kind == MediaKind.episode && entry.seriesName != null) {
    return '${entry.seriesName} • ${entry.name}';
  }
  return entry.name;
}

String _starPowerSubtitle(List<WatchHistoryEntry> entries) {
  final movies = entries
      .where((entry) => entry.kind == MediaKind.movie)
      .map((entry) => entry.id)
      .toSet()
      .length;
  final series = entries
      .where((entry) => entry.kind == MediaKind.episode)
      .map((entry) => entry.seriesId ?? entry.seriesName ?? entry.id)
      .toSet()
      .length;
  final parts = [
    if (series > 0) '$series series',
    if (movies > 0) '$movies movie${movies == 1 ? '' : 's'}',
  ];
  if (parts.isEmpty) return 'A recurring presence in your year.';
  return 'You watched ${parts.join(' and ')} featuring their work.';
}

enum _WatchTimeUnit { hours, minutes, days }

(double, String, int) _watchTimeParts(
  Duration duration, {
  required _WatchTimeUnit unit,
}) {
  final totalMinutes = duration.inMinutes;
  switch (unit) {
    case _WatchTimeUnit.minutes:
      return (totalMinutes.toDouble(), 'minutes', 0);
    case _WatchTimeUnit.days:
      final days = totalMinutes / Duration.minutesPerDay;
      return (days, 'days', days < 10 ? 1 : 0);
    case _WatchTimeUnit.hours:
      final hours = totalMinutes / Duration.minutesPerHour;
      return (
        hours >= 10 ? hours.roundToDouble() : hours,
        'hours',
        hours < 10 ? 1 : 0,
      );
  }
}

String _monthName(int month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month - 1];
}

String _weekdayName(int weekday) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return weekdays[weekday - 1];
}

String _hourRange(int hour) {
  String label(int value) {
    final normalized = value % 24;
    if (normalized == 0) return '12 AM';
    if (normalized == 12) return '12 PM';
    return normalized < 12 ? '$normalized AM' : '${normalized - 12} PM';
  }

  return '${label(hour)}–${label(hour + 1)}';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}
