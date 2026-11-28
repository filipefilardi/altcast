import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/format.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/core/widgets/edge_light_background.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/core/widgets/skeleton.dart';
import 'package:altcast/data/seerr/models.dart';
import 'package:altcast/data/seerr/seerr_repository.dart';
import 'package:altcast/features/search/seerr_discover_providers.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final connected = ref
          .read(seerrConnectionProvider)
          .maybeWhen(data: (session) => session != null, orElse: () => false);
      if (connected && !ref.read(seerrRequestsProvider).isLoading) {
        ref.invalidate(seerrRequestsProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(seerrConnectionProvider);

    return EdgeLightBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Requests')),
        body: connection.when(
          data: (session) => session == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: EmptyState(
                    icon: PiconsRegular.queue,
                    title: 'Connect Seerr',
                    message:
                        'Add your Seerr server in Settings to view requests.',
                    action: TextButton.icon(
                      onPressed: () => context.push('/settings'),
                      icon: const Icon(PiconsRegular.gear),
                      label: const Text('Open Settings'),
                    ),
                  ),
                )
              : const _RequestTabs(),
          loading: () => const _LoadingRequests(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ErrorStateView(
              title: 'Seerr failed',
              message: userFacingSeerrMessage(error),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTabs extends ConsumerWidget {
  const _RequestTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(seerrRequestsProvider);
    return DefaultTabController(
      length: 2,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textSecondary,
                  dividerHeight: 0,
                  labelPadding: EdgeInsets.symmetric(horizontal: 12),
                  tabs: [
                    Tab(text: 'Active'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
              Expanded(
                child: requests.when(
                  skipLoadingOnReload: true,
                  data: (items) => TabBarView(
                    children: [
                      for (final history in [false, true])
                        RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(seerrRequestsProvider);
                            await ref.read(seerrRequestsProvider.future);
                          },
                          child: _RequestsList(items: items, history: history),
                        ),
                    ],
                  ),
                  loading: () => const _LoadingRequests(),
                  error: (error, _) => ErrorStateView(
                    title: 'Requests failed',
                    message: userFacingSeerrMessage(error),
                    onRetry: () => ref.invalidate(seerrRequestsProvider),
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

enum _Section {
  downloading('Downloading', PiconsRegular.downloadSimple, AppColors.primary),
  failed('Failed requests', PiconsRegular.warningCircle, AppColors.error),
  processing('Processing', PiconsRegular.pulse, AppColors.primary),
  pending('Pending approval', PiconsRegular.clock, AppColors.primary),
  other('Requested', PiconsRegular.queue, AppColors.textSecondary),
  available(
    'Available',
    PiconsRegular.checkCircle,
    AppColors.success,
    history: true,
  ),
  declined('Declined', PiconsRegular.xCircle, AppColors.error, history: true),
  removed(
    'Removed',
    PiconsRegular.clockCounterClockwise,
    AppColors.textSecondary,
    history: true,
  );

  const _Section(this.title, this.icon, this.color, {this.history = false});
  final String title;
  final IconData icon;
  final Color color;
  final bool history;

  static _Section of(SeerrRequest item) {
    if (item.canRetry) return failed;
    if (item.status == SeerrRequestStatus.declined) return declined;
    if (item.status == SeerrRequestStatus.pending) return pending;
    if (item.mediaStatus == SeerrMediaStatus.deleted) return removed;
    if (item.mediaStatus == SeerrMediaStatus.available ||
        item.status == SeerrRequestStatus.completed) {
      return available;
    }
    if (item.downloads.isNotEmpty) return downloading;
    if (item.status == SeerrRequestStatus.approved ||
        item.mediaStatus == SeerrMediaStatus.processing ||
        item.mediaStatus == SeerrMediaStatus.partiallyAvailable) {
      return processing;
    }
    return other;
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({required this.items, required this.history});
  final List<SeerrRequest> items;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final groups = <_Section, List<SeerrRequest>>{};
    for (final item in items) {
      final section = _Section.of(item);
      if (section.history == history) (groups[section] ??= []).add(item);
    }
    return CustomScrollView(
      key: PageStorageKey(history),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: history
                  ? PiconsRegular.clockCounterClockwise
                  : PiconsRegular.queue,
              title: history ? 'No request history' : 'No active requests',
              message: history
                  ? 'Finished requests will appear here.'
                  : 'New and in-progress requests will appear here.',
            ),
          ),
        for (final section in _Section.values)
          if (groups[section] case final items?)
            _RequestSection(
              key: ValueKey(section),
              section: section,
              items: items,
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _RequestSection extends StatefulWidget {
  const _RequestSection({
    super.key,
    required this.section,
    required this.items,
  });
  final _Section section;
  final List<SeerrRequest> items;

  @override
  State<_RequestSection> createState() => _RequestSectionState();
}

class _RequestSectionState extends State<_RequestSection> {
  static const _previewCount = 3;
  bool _expanded = false;

  static int _newestFirst(SeerrRequest a, SeerrRequest b) {
    final first = a.createdAt;
    final second = b.createdAt;
    if (first == null && second != null) return 1;
    if (second == null && first != null) return -1;
    final byDate = second?.compareTo(first!) ?? 0;
    return byDate == 0 ? b.id.compareTo(a.id) : byDate;
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final preview =
        section == _Section.downloading ||
        section == _Section.failed ||
        section == _Section.processing;
    final items = preview
        ? (widget.items.toList()..sort((a, b) {
            if (section == _Section.downloading &&
                a.hasActiveDownload != b.hasActiveDownload) {
              return a.hasActiveDownload ? -1 : 1;
            }
            return _newestFirst(a, b);
          }))
        : widget.items;
    final canExpand = preview && items.length > _previewCount;
    final visibleCount = canExpand && !_expanded ? _previewCount : items.length;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                header: true,
                child: Row(
                  children: [
                    Icon(section.icon, size: 22, color: section.color),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        section.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedSliver(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: .56),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            sliver: SliverList.separated(
              itemCount: visibleCount + (canExpand ? 1 : 0),
              findItemIndexCallback: (key) {
                final index = items.indexWhere(
                  (item) => ValueKey(item.id) == key,
                );
                return index < 0 || index >= visibleCount ? null : index;
              },
              itemBuilder: (_, index) {
                if (index == visibleCount) {
                  final label = switch (section) {
                    _Section.downloading => 'downloads',
                    _Section.failed => 'failed requests',
                    _ => 'waiting requests',
                  };
                  return Semantics(
                    expanded: _expanded,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                        ),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      iconAlignment: IconAlignment.end,
                      icon: Icon(
                        _expanded
                            ? PiconsRegular.caretUp
                            : PiconsRegular.caretDown,
                        size: 16,
                      ),
                      label: Text(
                        _expanded
                            ? 'Show fewer'
                            : 'Show all ${items.length} $label',
                      ),
                    ),
                  );
                }
                return _RequestTile(
                  key: ValueKey(items[index].id),
                  request: items[index],
                  section: section,
                  borderRadius: BorderRadius.vertical(
                    top: index == 0 ? const Radius.circular(15) : Radius.zero,
                    bottom: index == visibleCount - 1 && !canExpand
                        ? const Radius.circular(15)
                        : Radius.zero,
                  ),
                );
              },
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: AppColors.divider,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingRequests extends StatelessWidget {
  const _LoadingRequests();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Skeleton.group(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Skeleton.box(width: double.infinity, height: 100),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ],
  );
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({
    super.key,
    required this.request,
    required this.section,
    required this.borderRadius,
  });
  final BorderRadius borderRadius;
  final SeerrRequest request;
  final _Section section;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _retrying = false;
  String? _updatingStatus;
  String? _retryError;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final tmdbId = request.tmdbId;
    final missingTitle =
        request.title == null || request.title!.startsWith('TMDb #');
    SeerrMediaDetails? detail;
    if (tmdbId != null &&
        (request.mediaType == SeerrMediaType.tv ||
            request.mediaType == SeerrMediaType.movie) &&
        (request.backdropUrl == null || missingTitle)) {
      detail = ref
          .watch(
            seerrDetailsProvider(
              SeerrDetailsKey(id: tmdbId, mediaType: request.mediaType),
            ),
          )
          .asData
          ?.value;
    }
    final title =
        (missingTitle ? detail?.title : null) ??
        request.title ??
        'Request #${request.id}';
    final backdrop = request.backdropUrl ?? detail?.backdropUrl;
    final date = request.createdAt?.toLocal();
    final requester = request.requestedByName?.trim();
    final canOpen =
        widget.section == _Section.available && request.canOpenInLibrary;
    final status = _statusContent(request);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          children: [
            if (backdrop != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, .28, 1],
                      ).createShader(bounds),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xEF111820),
                              Color(0xBB111820),
                              Color(0x70111820),
                              Color(0xAA111820),
                            ],
                            stops: [0, .32, .74, 1],
                          ),
                        ),
                        child: LocalOrNetworkImage(
                          source: backdrop,
                          alignment: const Alignment(0, -.30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canOpen ? _openTitle : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (date != null) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: MaterialLocalizations.of(context)
                                  .formatFullDate(date),
                              child: Text(
                                MaterialLocalizations.of(context)
                                    .formatShortMonthDay(date),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _scope(request),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (requester != null &&
                                    requester.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        PiconsRegular.user,
                                        size: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          requester,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          semanticsLabel:
                                              'Requested by $requester',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (request.canRetry) ...[
                            const SizedBox(width: 8),
                            _RequestActionButton(
                              label: 'Retry',
                              icon: PiconsRegular.arrowsClockwise,
                              color: AppColors.error,
                              loading: _retrying,
                              onPressed: _retrying ? null : _retry,
                            ),
                          ],
                          if (canOpen)
                            const Icon(
                              PiconsRegular.caretRight,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 9),
                        status,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scope(SeerrRequest request) {
    if (request.seasons.isEmpty) return request.mediaType.label;
    final seasons = request.seasons.toSet().toList()..sort();
    if (seasons.length == 1) return 'Season ${seasons.single}';
    if (seasons.last - seasons.first == seasons.length - 1) {
      return 'Seasons ${seasons.first}–${seasons.last}';
    }
    return 'Seasons ${seasons.join(', ')}';
  }

  Widget? _statusContent(SeerrRequest request) {
    switch (widget.section) {
      case _Section.failed:
        final reason = _retryError ?? request.failureReason;
        if (reason == null || reason.trim().isEmpty) return null;
        return _StatusStrip(
          section: widget.section,
          child: Text(
            reason,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        );
      case _Section.downloading:
      case _Section.processing:
        return _TransferProgress(request: request);
      case _Section.pending:
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _RequestActionButton(
              label: 'Approve',
              icon: PiconsRegular.check,
              color: AppColors.success,
              loading: _updatingStatus == 'approve',
              onPressed: _updatingStatus == null
                  ? () => _updateStatus('approve')
                  : null,
            ),
            _RequestActionButton(
              label: 'Reject',
              icon: PiconsRegular.x,
              color: AppColors.error,
              loading: _updatingStatus == 'decline',
              onPressed: _updatingStatus == null
                  ? () => _updateStatus('decline')
                  : null,
            ),
          ],
        );
      default:
        return null;
    }
  }

  void _openTitle() {
    final itemId = widget.request.jellyfinItemId;
    if (itemId == null || itemId.isEmpty) return;
    final path = widget.request.mediaType == SeerrMediaType.tv
        ? '/series/$itemId'
        : '/movie/$itemId';
    context.push(path);
  }

  Future<void> _updateStatus(String status) async {
    if (_updatingStatus != null) return;
    setState(() => _updatingStatus = status);
    try {
      await ref
          .read(seerrRepositoryProvider)
          .updateRequestStatus(requestId: widget.request.id, status: status);
      if (!mounted) return;
      ref.invalidate(seerrRequestsProvider);
      showAppSnackBar(
        context,
        status == 'approve' ? 'Request approved.' : 'Request rejected.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${status == 'approve' ? 'Approve' : 'Reject'} failed: ${userFacingSeerrMessage(error)}',
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = null);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      await ref.read(seerrRepositoryProvider).retryRequest(widget.request.id);
      if (!mounted) return;
      ref.invalidate(seerrRequestsProvider);
      showAppSnackBar(context, 'Retry sent to Seerr.');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _retryError = 'Retry failed: ${userFacingSeerrMessage(error)}',
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }
}

class _RequestActionButton extends StatelessWidget {
  const _RequestActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.10),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class _TransferProgress extends StatefulWidget {
  const _TransferProgress({required this.request});

  final SeerrRequest request;

  @override
  State<_TransferProgress> createState() => _TransferProgressState();
}

class _TransferProgressState extends State<_TransferProgress> {
  bool _expanded = true;

  static String _etaLabel(String eta) {
    // Seerr may return either a clock duration or a human-readable estimate.
    final clock = RegExp(r'^(?:(\d{1,6})\.)?(\d{1,6}):([0-5]\d):([0-5]\d)$')
        .firstMatch(eta);
    if (clock == null) return 'ETA $eta';
    final duration = Duration(
      days: int.parse(clock[1] ?? '0'),
      hours: int.parse(clock[2]!),
      minutes: int.parse(clock[3]!),
      seconds: int.parse(clock[4]!),
    );
    if (duration.inMinutes == 0) return 'Under 1 min left';
    final minutes = (duration.inSeconds / 60).ceil();
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$minutes min left';
    return remainder == 0 ? '${hours}h left' : '${hours}h ${remainder}m left';
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final bytes = request.downloadBytes;
    final total = bytes?.total ?? request.totalDownloadSize;
    final fraction = bytes == null ? null : bytes.received / bytes.total;
    final percent = bytes == null
        ? null
        : _percent(bytes.received, bytes.total);
    final eta = fraction == 1 ? null : request.downloadEta;
    final count = request.downloads.length;
    final contextLine = [
      if (request.mediaType == SeerrMediaType.tv && count > 0)
        'Series queue · $count ${count == 1 ? 'transfer' : 'transfers'}',
      if (request.mediaStatus == SeerrMediaStatus.partiallyAvailable)
        'Partially available',
    ];
    if (count == 0) {
      return Text(
        ['Waiting for queue details', ...contextLine].join(' · '),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final label = switch (fraction) {
      1.0 => 'Transfer complete',
      0.0 when request.hasActiveDownload => 'Starting download',
      _ when request.hasActiveDownload => 'Downloading',
      _
          when request.downloads.every(
            (d) => d.status.trim().toLowerCase() == 'paused',
          ) =>
        'Paused',
      _ => 'In download queue',
    };
    const secondary = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    final hasDetails =
        percent != null ||
        eta != null ||
        total != null ||
        contextLine.isNotEmpty;
    final heading = Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasDetails) ...[
                const SizedBox(width: 4),
                Icon(
                  _expanded ? PiconsRegular.caretUp : PiconsRegular.caretDown,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ],
            ],
          ),
        ),
        if (percent != null) ...[
          const SizedBox(width: 8),
          Text(
            percent,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 5,
      children: [
        if (hasDetails)
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: heading,
              ),
            ),
          )
        else
          heading,
        if (_expanded) ...[
          if (fraction != null)
            LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(8),
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
              trackGap: 0,
              semanticsLabel: request.mediaType == SeerrMediaType.tv
                  ? 'Series queue download progress'
                  : 'Download progress',
              semanticsValue: percent,
            ),
          if (eta != null || total != null)
            Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (eta != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            PiconsRegular.clock,
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        TextSpan(text: '  ${_etaLabel(eta)}'),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (total != null)
                  Text('${formatBytes(total)} total', style: secondary),
              ],
            ),
          if (contextLine.isNotEmpty)
            Text(contextLine.join(' · '), style: secondary),
        ],
      ],
    );
  }

  static String _percent(int received, int total) {
    final percent = received * 100 ~/ total;
    return percent == 0 && received > 0 ? '<1%' : '$percent%';
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.section, required this.child});
  final _Section section;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: section.color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(section.icon, color: section.color, size: 17),
        const SizedBox(width: 7),
        Expanded(child: child),
      ],
    ),
  );
}
