import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
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
      if (connected) ref.invalidate(seerrRequestsProvider);
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
    final filter = ref.watch(seerrRequestsFilterProvider);
    final requests = ref.watch(seerrRequestsProvider);

    return EdgeLightBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Requests')),
        body: connection.when(
          data: (session) {
            if (session == null) {
              return Padding(
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
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(seerrRequestsProvider);
                await ref.read(seerrRequestsProvider.future);
              },
              child: requests.when(
                skipLoadingOnReload: true,
                data: (items) =>
                    _RequestsList(items: items, selectedFilter: filter),
                loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                  children: [
                    _RequestFilters(selected: filter),
                    const SizedBox(height: 18),
                    const _RequestsSkeleton(),
                  ],
                ),
                error: (e, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    ErrorStateView(
                      title: 'Requests failed',
                      message: userFacingSeerrMessage(e),
                      onRetry: () => ref.invalidate(seerrRequestsProvider),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              _RequestFilters(selected: filter),
              const SizedBox(height: 18),
              const _RequestsSkeleton(),
            ],
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ErrorStateView(
              title: 'Seerr failed',
              message: userFacingSeerrMessage(e),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({required this.items, required this.selectedFilter});

  final List<SeerrRequest> items;
  final String selectedFilter;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where((request) => _matchesFilter(request, selectedFilter))
        .toList(growable: false);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
          children: [
            _RequestFilters(selected: selectedFilter),
            const SizedBox(height: 18),
            if (visibleItems.isEmpty)
              const EmptyState(
                icon: PiconsRegular.queue,
                title: 'No requests',
                message: 'Requested movies and shows will appear here.',
              )
            else
              for (final request in visibleItems) ...[
                _RequestTile(request: request),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  bool _matchesFilter(SeerrRequest request, String filter) {
    return switch (filter) {
      'pending' => request.status == SeerrRequestStatus.pending,
      'processing' =>
        request.status == SeerrRequestStatus.approved &&
            request.mediaStatus != SeerrMediaStatus.available &&
            request.mediaStatus != SeerrMediaStatus.deleted,
      'available' =>
        request.mediaStatus == SeerrMediaStatus.available ||
            request.status == SeerrRequestStatus.completed,
      'failed' =>
        request.status == SeerrRequestStatus.failed ||
            request.status == SeerrRequestStatus.declined,
      _ => true,
    };
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RequestFilters extends ConsumerWidget {
  const _RequestFilters({required this.selected});

  final String selected;

  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('pending', 'Pending'),
    ('processing', 'Processing'),
    ('available', 'Available'),
    ('failed', 'Failed'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _filters) ...[
            _FilterPill(
              label: filter.$2,
              selected: selected == filter.$1,
              onTap: () => ref
                  .read(seerrRequestsFilterProvider.notifier)
                  .setFilter(filter.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.17)
          : Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: selected ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.44)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request});

  final SeerrRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _retrying = false;
  String? _updatingStatus;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final created = request.createdAt;
    final seasons = request.seasons.isEmpty
        ? null
        : 'S${request.seasons.map((s) => s.toString()).join(', S')}';
    final shortDate = created == null ? null : _shortDate(created);
    final requester = request.requestedByName == null
        ? null
        : 'Requested by ${request.requestedByName}';
    final meta = [
      request.mediaType.label,
      ?seasons,
      ?requester,
      ?shortDate,
    ].join(' • ');
    final statusColor = _statusColor(request);
    final progress = request.progress;
    final processingDetail = request.processingDetail;
    final canTap = request.canOpenInLibrary;

    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canTap ? _openTitle : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 52,
                    height: 76,
                    child: ColoredBox(
                      color: statusColor.withValues(alpha: 0.12),
                      child: LocalOrNetworkImage(
                        source: request.posterUrl ?? request.backdropUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_) => Icon(
                          request.mediaType == SeerrMediaType.movie
                              ? PiconsRegular.televisionSimple
                              : PiconsRegular.sparkle,
                          color: statusColor,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              request.title ?? 'Request #${request.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _RequestStatusPill(request: request),
                          if (canTap) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              PiconsRegular.caretRight,
                              color: AppColors.textSecondary,
                              size: 17,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          if (request.requestedByName != null) ...[
                            Icon(
                              PiconsRegular.user,
                              size: 13,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.9,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (processingDetail != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          processingDetail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (request.status == SeerrRequestStatus.pending) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
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
                        ),
                      ] else if (request.canRetry) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _RetryButton(
                            loading: _retrying,
                            onPressed: _retry,
                          ),
                        ),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              statusColor,
                            ),
                          ),
                        ),
                      ] else if (request.mediaStatus ==
                          SeerrMediaStatus.processing) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Waiting for Seerr queue details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ] else
                        const SizedBox(height: 2),
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

  void _openTitle() {
    final itemId = widget.request.jellyfinItemId;
    if (itemId == null || itemId.isEmpty) return;
    final path = widget.request.mediaType == SeerrMediaType.tv
        ? '/series/$itemId'
        : '/movie/$itemId';
    context.push(path);
  }

  String _shortDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  Future<void> _updateStatus(String status) async {
    if (_updatingStatus != null) return;
    setState(() => _updatingStatus = status);
    try {
      await ref
          .read(seerrRepositoryProvider)
          .updateRequestStatus(requestId: widget.request.id, status: status);
      ref.invalidate(seerrRequestsProvider);
      if (!mounted) return;
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
    setState(() => _retrying = true);
    try {
      await ref.read(seerrRepositoryProvider).retryRequest(widget.request.id);
      ref.invalidate(seerrRequestsProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Retry sent to Seerr.');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Retry failed: ${userFacingSeerrMessage(error)}',
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(PiconsRegular.arrowsClockwise, size: 16),
      label: const Text('Retry'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.error,
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
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
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class _RequestStatusPill extends StatelessWidget {
  const _RequestStatusPill({required this.request});

  final SeerrRequest request;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          request.statusLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Color _statusColor(SeerrRequest request) {
  if (request.status == SeerrRequestStatus.failed ||
      request.status == SeerrRequestStatus.declined) {
    return AppColors.error;
  }
  if (request.status == SeerrRequestStatus.pending) {
    return AppColors.primary;
  }
  if (request.mediaStatus == SeerrMediaStatus.available) {
    return AppColors.success;
  }
  if (request.mediaStatus == SeerrMediaStatus.processing ||
      request.mediaStatus == SeerrMediaStatus.partiallyAvailable) {
    return AppColors.primary;
  }
  return switch (request.status) {
    SeerrRequestStatus.pending => AppColors.primary,
    SeerrRequestStatus.approved => AppColors.success,
    SeerrRequestStatus.completed => AppColors.success,
    SeerrRequestStatus.declined => AppColors.error,
    SeerrRequestStatus.failed => AppColors.error,
    SeerrRequestStatus.unknown => AppColors.textTertiary,
  };
}

class _RequestsSkeleton extends StatelessWidget {
  const _RequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
        children: [
          for (var i = 0; i < 6; i++) ...[
            Skeleton.box(width: double.infinity, height: 82),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
