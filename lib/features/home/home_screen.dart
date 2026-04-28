import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../auth/auth_controller.dart';
import 'home_providers.dart';
import 'widgets/poster_card.dart';
import 'widgets/resume_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final username =
        auth is AuthAuthenticated ? auth.session.username : null;

    final resumeAsync = ref.watch(continueWatchingProvider);
    final moviesAsync = ref.watch(recentMoviesProvider);
    final showsAsync = ref.watch(recentShowsProvider);

    final everythingFailed = resumeAsync.hasError &&
        moviesAsync.hasError &&
        showsAsync.hasError;
    final everythingEmpty = resumeAsync.value?.isEmpty == true &&
        moviesAsync.value?.isEmpty == true &&
        showsAsync.value?.isEmpty == true;

    Future<void> refresh() async {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(recentMoviesProvider);
      ref.invalidate(recentShowsProvider);
      await Future.wait([
        ref.read(continueWatchingProvider.future).catchError((_) => <BrowseItem>[]),
        ref.read(recentMoviesProvider.future).catchError((_) => <BrowseItem>[]),
        ref.read(recentShowsProvider.future).catchError((_) => <BrowseItem>[]),
      ]);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _Greeting(username: username),
            const SizedBox(height: 24),
            if (everythingFailed)
              ErrorStateView(
                title: "Couldn't load library",
                message: 'Pull to retry, or check your server connection.',
                onRetry: refresh,
              )
            else if (everythingEmpty)
              EmptyState(
                icon: Icons.movie_filter_outlined,
                title: 'Nothing here yet',
                message: 'Add some movies or shows to your Jellyfin server.',
                action: TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              )
            else ...[
              _Section<List<BrowseItem>>(
                title: 'Continue Watching',
                state: resumeAsync,
                onRetry: () => ref.invalidate(continueWatchingProvider),
                builder: (items) => _ResumeRow(items: items),
                hideWhenEmpty: true,
                skeletonHeight: 168,
              ),
              _Section<List<BrowseItem>>(
                title: 'Recently added movies',
                state: moviesAsync,
                onRetry: () => ref.invalidate(recentMoviesProvider),
                builder: (items) => _PosterRow(items: items),
                hideWhenEmpty: true,
                skeletonHeight: 248,
              ),
              _Section<List<BrowseItem>>(
                title: 'New episodes',
                state: showsAsync,
                onRetry: () => ref.invalidate(recentShowsProvider),
                builder: (items) => _PosterRow(items: items),
                hideWhenEmpty: true,
                skeletonHeight: 248,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.username});
  final String? username;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AltCast',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 4),
        Text(
          username == null ? 'Welcome' : 'Welcome back, $username',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.state,
    required this.onRetry,
    required this.builder,
    required this.skeletonHeight,
    this.hideWhenEmpty = false,
  });

  final String title;
  final AsyncValue<T> state;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;
  final double skeletonHeight;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final isEmpty = state.value is List && (state.value as List).isEmpty;
    if (state.hasValue && hideWhenEmpty && isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (state.isLoading)
          _SkeletonRow(height: skeletonHeight)
        else if (state.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ErrorStateView(
              title: "Couldn't load $title",
              onRetry: onRetry,
            ),
          )
        else if (state.hasValue)
          builder(state.requireValue),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Skeleton.group(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) =>
              Skeleton.box(width: 132, height: height - 8),
        ),
      ),
    );
  }
}

class _ResumeRow extends StatelessWidget {
  const _ResumeRow({required this.items});
  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => ResumeCard(
          item: items[i],
          onTap: () => _comingSoon(context),
        ),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.items});
  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => PosterCard(
          item: items[i],
          onTap: () => _comingSoon(context),
        ),
      ),
    );
  }
}

void _comingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Detail screen coming soon'),
        backgroundColor: AppColors.surfaceHighlight,
      ),
    );
}
