import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/core/utils/navigation.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/watch_history_store.dart';
import 'package:altcast/features/auth/auth_controller.dart';
import 'package:altcast/features/year_review/widgets/year_review_promo_card.dart';

enum _HistoryType {
  all('All', 'Movie,Episode'),
  movies('Movies', 'Movie'),
  episodes('Episodes', 'Episode');

  const _HistoryType(this.label, this.itemTypes);

  final String label;
  final String itemTypes;
}

class WatchHistoryScreen extends ConsumerStatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  ConsumerState<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends ConsumerState<WatchHistoryScreen> {
  static const _pageSize = 30;

  List<WatchHistoryEntry> _entries = [];
  int _nextIndex = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _inflight = false;
  Object? _error;
  _HistoryType _type = _HistoryType.all;

  JellyfinSession? get _session {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.session : null;
  }

  List<WatchHistoryEntry> get _visibleEntries {
    return _entries
        .where((entry) {
          return switch (_type) {
            _HistoryType.all => true,
            _HistoryType.movies => entry.kind == MediaKind.movie,
            _HistoryType.episodes => entry.kind == MediaKind.episode,
          };
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch history'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          PopupMenuButton<_HistoryType>(
            enabled: !_inflight,
            tooltip: 'Filter',
            initialValue: _type,
            icon: const Icon(PiconsRegular.funnelSimple),
            onSelected: (type) {
              if (type == _type) return;
              setState(() => _type = type);
              _reload();
            },
            itemBuilder: (_) => [
              for (final type in _HistoryType.values)
                PopupMenuItem(value: type, child: Text(type.label)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: _buildBody(),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    if (_inflight) return;
    final session = _session;
    if (session == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _nextIndex = 0;
      _hasMore = true;
    });

    final cached = await ref.read(watchHistoryStoreProvider).read(session);
    if (!mounted) return;
    setState(() {
      _entries = cached;
      _loading = cached.isEmpty;
    });
    await _loadMore(reconcileAvailability: true);
  }

  Future<void> _loadMore({bool reconcileAvailability = false}) async {
    if (_inflight || !_hasMore) return;
    final session = _session;
    if (session == null) return;

    _inflight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final page = await repo.watchHistory(
        startIndex: _nextIndex,
        limit: _pageSize,
        itemTypes: _type.itemTypes,
      );
      var merged = mergeWatchHistory(_entries, page.items);

      if (reconcileAvailability) {
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
          // A failed availability check must never make cached history look
          // deleted. Keep the last known state and try again next refresh.
        }
      }

      await ref.read(watchHistoryStoreProvider).write(session, merged);
      if (!mounted) return;
      setState(() {
        _entries = merged;
        _nextIndex += page.fetchedItemCount ?? page.items.length;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      _inflight = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_hasMore || _inflight) return false;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 600) {
      _loadMore();
    }
    return false;
  }

  Widget _buildBody() {
    final visible = _visibleEntries;
    if (_loading && visible.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && visible.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          ErrorStateView(
            title: "Couldn't load watch history",
            message: userFacingNetworkMessage(_error!),
            onRetry: _reload,
          ),
        ],
      );
    }
    if (visible.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.clock,
              title: 'No watch history yet',
              message: _type == _HistoryType.all
                  ? 'Movies and episodes you finish will appear here.'
                  : 'No finished ${_type.label.toLowerCase()} found.',
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const YearReviewPromoCard(),
        const SizedBox(height: 16),
        for (var i = 0; i < visible.length; i++) ...[
          if (_startsDateGroup(visible, i))
            _DateHeader(date: visible[i].watchedAt!.toLocal()),
          _HistoryRow(
            entry: visible[i],
            onTap: visible[i].isAvailable
                ? () => openItemDetail(context, visible[i].toBrowseItem())
                : null,
          ),
          if (i < visible.length - 1) const SizedBox(height: 10),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ErrorStateView(
              title: "Couldn't refresh watch history",
              message: userFacingNetworkMessage(_error!),
              onRetry: _reload,
            ),
          )
        else if (_hasMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  bool _startsDateGroup(List<WatchHistoryEntry> entries, int index) {
    final current = entries[index].watchedAt?.toLocal();
    if (current == null) return false;
    if (index == 0) return true;
    final previous = entries[index - 1].watchedAt?.toLocal();
    return previous == null || !_sameDate(current, previous);
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        _dateHeaderLabel(date).toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.entry, required this.onTap});

  final WatchHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final imageUrl = repo.backdropUrl(
      entry.id,
      entry.backdropTag,
      fallbackPrimaryTag: entry.imageTag,
    );
    final playedAt = entry.watchedAt?.toLocal();

    return Opacity(
      opacity: entry.isAvailable ? 1 : 0.62,
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 112,
                    height: 64,
                    child: ColoredBox(
                      color: AppColors.surfaceHighlight,
                      child: LocalOrNetworkImage(
                        source: imageUrl,
                        errorBuilder: (_) => const Center(
                          child: Icon(
                            PiconsRegular.televisionSimple,
                            color: AppColors.textTertiary,
                          ),
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
                        _historyTitle(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _historySubtitle(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (playedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _timeLabel(playedAt),
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (!entry.isAvailable) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'NO LONGER AVAILABLE',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
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
    );
  }
}

String _historyTitle(WatchHistoryEntry entry) {
  if (entry.kind == MediaKind.episode && entry.seriesName != null) {
    return entry.seriesName!;
  }
  return entry.name;
}

String _historySubtitle(WatchHistoryEntry entry) {
  if (entry.kind == MediaKind.episode) {
    return [?entry.subtitle, entry.name].join(' • ');
  }
  return entry.subtitle ?? 'Movie';
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateHeaderLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final value = DateTime(date.year, date.month, date.day);
  if (value == today) return 'Today';
  if (value == today.subtract(const Duration(days: 1))) return 'Yesterday';
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _timeLabel(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour < 12 ? 'AM' : 'PM';
  return 'Watched at $hour:$minute $suffix';
}
