import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/person_credit.dart';
import 'package:altcast/data/local/watch_history_store.dart';

class YearReviewSummary {
  const YearReviewSummary({
    required this.year,
    required this.entries,
    required this.moviesWatched,
    required this.episodesWatched,
    required this.uniqueSeries,
    required this.totalDaysActive,
    required this.monthlyActivity,
    required this.monthlyMovies,
    required this.monthlyEpisodes,
    required this.weekdayActivity,
    required this.hourlyActivity,
    required this.estimatedWatchTime,
    required this.topGenres,
    this.topSeries,
    this.starPower,
    this.longestEpisodeStreak,
    this.busiestMonth,
    this.busiestWeekday,
    this.busiestHour,
    this.firstWatched,
    this.lastWatched,
  });

  final int year;
  final List<WatchHistoryEntry> entries;
  final int moviesWatched;
  final int episodesWatched;
  final int uniqueSeries;
  final int totalDaysActive;
  final List<int> monthlyActivity;
  final List<int> monthlyMovies;
  final List<int> monthlyEpisodes;
  final List<int> weekdayActivity;
  final List<int> hourlyActivity;
  final Duration estimatedWatchTime;
  final List<GenreReview> topGenres;
  final TopSeriesReview? topSeries;
  final StarPowerReview? starPower;
  final EpisodeStreakReview? longestEpisodeStreak;
  final int? busiestMonth;
  final int? busiestWeekday;
  final int? busiestHour;
  final WatchHistoryEntry? firstWatched;
  final WatchHistoryEntry? lastWatched;

  bool get isEmpty => entries.isEmpty;

  factory YearReviewSummary.fromEntries(
    Iterable<WatchHistoryEntry> source,
    int year,
  ) {
    final entries =
        source
            .where((entry) => entry.watchedAt?.toLocal().year == year)
            .toList()
          ..sort(_newestFirst);

    final monthlyActivity = List<int>.filled(12, 0);
    final monthlyMovies = List<int>.filled(12, 0);
    final monthlyEpisodes = List<int>.filled(12, 0);
    final weekdayActivity = List<int>.filled(7, 0);
    final hourlyActivity = List<int>.filled(24, 0);
    final seriesEntries = <String, List<WatchHistoryEntry>>{};
    final genreCounts = <String, _NamedCount>{};
    final personEntries = <String, _PersonCount>{};
    var totalTicks = 0;

    for (final entry in entries) {
      final watchedAt = entry.watchedAt?.toLocal();
      if (watchedAt != null) {
        final monthIndex = watchedAt.month - 1;
        monthlyActivity[monthIndex]++;
        weekdayActivity[watchedAt.weekday - 1]++;
        hourlyActivity[watchedAt.hour]++;
        if (entry.kind == MediaKind.movie) monthlyMovies[monthIndex]++;
        if (entry.kind == MediaKind.episode) monthlyEpisodes[monthIndex]++;
      }
      totalTicks += entry.runTimeTicks ?? 0;

      for (final genre in entry.genres.toSet()) {
        final trimmed = genre.trim();
        if (trimmed.isEmpty) continue;
        final key = trimmed.toLowerCase();
        final current = genreCounts[key];
        genreCounts[key] = _NamedCount(trimmed, (current?.count ?? 0) + 1);
      }

      final peopleSeen = <String>{};
      for (final person in entry.people) {
        final type = person.type?.toLowerCase();
        if (type != 'actor' && type != 'director') continue;
        final key = person.id?.isNotEmpty == true
            ? person.id!
            : '${person.name.toLowerCase()}:$type';
        if (!peopleSeen.add(key)) continue;
        final current = personEntries[key];
        personEntries[key] = _PersonCount(
          person: current?.person ?? person,
          entries: [...?current?.entries, entry],
        );
      }

      if (entry.kind != MediaKind.episode) continue;
      final key = entry.seriesId ?? entry.seriesName;
      if (key == null || key.isEmpty) continue;
      seriesEntries.putIfAbsent(key, () => []).add(entry);
    }

    final sortedSeries = seriesEntries.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final sortedGenres = genreCounts.values.toList()
      ..sort((a, b) {
        final count = b.count.compareTo(a.count);
        return count != 0 ? count : a.name.compareTo(b.name);
      });
    final sortedPeople = personEntries.values.toList()
      ..sort((a, b) {
        final count = b.entries.length.compareTo(a.entries.length);
        return count != 0 ? count : a.person.name.compareTo(b.person.name);
      });

    int? busiestMonth;
    var busiestCount = 0;
    for (var index = 0; index < monthlyActivity.length; index++) {
      if (monthlyActivity[index] > busiestCount) {
        busiestCount = monthlyActivity[index];
        busiestMonth = index + 1;
      }
    }

    final busiestWeekday = _highestIndex(weekdayActivity);
    final busiestHour = _highestIndex(hourlyActivity, zeroBased: true);

    final topSeriesEntries = sortedSeries.isEmpty ? null : sortedSeries.first;
    final star = sortedPeople.isEmpty ? null : sortedPeople.first;
    return YearReviewSummary(
      year: year,
      entries: entries,
      moviesWatched: entries
          .where((entry) => entry.kind == MediaKind.movie)
          .length,
      episodesWatched: entries
          .where((entry) => entry.kind == MediaKind.episode)
          .length,
      uniqueSeries: seriesEntries.length,
      totalDaysActive: entries
          .map((entry) => entry.watchedAt?.toLocal())
          .whereType<DateTime>()
          .map((date) => DateTime(date.year, date.month, date.day))
          .toSet()
          .length,
      monthlyActivity: monthlyActivity,
      monthlyMovies: monthlyMovies,
      monthlyEpisodes: monthlyEpisodes,
      weekdayActivity: weekdayActivity,
      hourlyActivity: hourlyActivity,
      estimatedWatchTime: Duration(microseconds: totalTicks ~/ 10),
      topGenres: sortedGenres
          .take(3)
          .map(
            (genre) => GenreReview(
              name: genre.name,
              count: genre.count,
              percentage: entries.isEmpty ? 0 : genre.count / entries.length,
            ),
          )
          .toList(growable: false),
      topSeries: topSeriesEntries == null
          ? null
          : TopSeriesReview(
              name: topSeriesEntries.first.seriesName ?? 'Unknown series',
              entries: topSeriesEntries,
            ),
      starPower: star == null
          ? null
          : StarPowerReview(person: star.person, entries: star.entries),
      longestEpisodeStreak: _longestStreak(seriesEntries.values),
      busiestMonth: busiestMonth,
      busiestWeekday: busiestWeekday,
      busiestHour: busiestHour,
      firstWatched: entries.isEmpty ? null : entries.last,
      lastWatched: entries.isEmpty ? null : entries.first,
    );
  }
}

int? _highestIndex(List<int> values, {bool zeroBased = false}) {
  var highest = 0;
  int? result;
  for (var index = 0; index < values.length; index++) {
    if (values[index] > highest) {
      highest = values[index];
      result = zeroBased ? index : index + 1;
    }
  }
  return result;
}

class TopSeriesReview {
  const TopSeriesReview({required this.name, required this.entries});

  final String name;
  final List<WatchHistoryEntry> entries;
  int get episodeCount => entries.length;
}

class GenreReview {
  const GenreReview({
    required this.name,
    required this.count,
    required this.percentage,
  });

  final String name;
  final int count;
  final double percentage;
}

class StarPowerReview {
  const StarPowerReview({required this.person, required this.entries});

  final PersonCredit person;
  final List<WatchHistoryEntry> entries;
}

class EpisodeStreakReview {
  const EpisodeStreakReview({
    required this.seriesName,
    required this.entries,
    required this.startedAt,
    required this.endedAt,
  });

  final String seriesName;
  final List<WatchHistoryEntry> entries;
  final DateTime startedAt;
  final DateTime endedAt;
}

class _NamedCount {
  const _NamedCount(this.name, this.count);

  final String name;
  final int count;
}

class _PersonCount {
  const _PersonCount({required this.person, required this.entries});

  final PersonCredit person;
  final List<WatchHistoryEntry> entries;
}

EpisodeStreakReview? _longestStreak(
  Iterable<List<WatchHistoryEntry>> groupedEpisodes,
) {
  List<WatchHistoryEntry> longest = const [];
  for (final source in groupedEpisodes) {
    final episodes = source.where((entry) => entry.watchedAt != null).toList()
      ..sort((a, b) => a.watchedAt!.compareTo(b.watchedAt!));
    var current = <WatchHistoryEntry>[];
    for (final episode in episodes) {
      final closeToPrevious =
          current.isNotEmpty &&
          episode.watchedAt!.difference(current.last.watchedAt!) <=
              const Duration(hours: 2);
      if (!closeToPrevious) current = [];
      current.add(episode);
      if (current.length > longest.length) longest = [...current];
    }
  }
  if (longest.length < 2) return null;
  return EpisodeStreakReview(
    seriesName: longest.first.seriesName ?? 'Unknown series',
    entries: longest,
    startedAt: longest.first.watchedAt!,
    endedAt: longest.last.watchedAt!,
  );
}

int _newestFirst(WatchHistoryEntry a, WatchHistoryEntry b) {
  final aDate = a.watchedAt;
  final bDate = b.watchedAt;
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

bool shouldShowYearReviewPromo(DateTime date) =>
    date.month == DateTime.december || date.month == DateTime.january;

int featuredYearReviewYear(DateTime date) =>
    date.month == DateTime.january ? date.year - 1 : date.year;
