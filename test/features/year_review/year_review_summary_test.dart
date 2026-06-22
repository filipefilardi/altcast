import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/person_credit.dart';
import 'package:altcast/data/local/watch_history_store.dart';
import 'package:altcast/features/year_review/year_review_summary.dart';

void main() {
  test('builds honest yearly counts and highlights', () {
    final entries = [
      _entry(
        id: 'movie-1',
        name: 'First Movie',
        kind: MediaKind.movie,
        date: DateTime.utc(2026, 1, 4),
        runtimeMinutes: 90,
        genres: const ['Science Fiction'],
        people: const [PersonCredit(name: 'Ada Star', type: 'Actor')],
      ),
      _entry(
        id: 'episode-1',
        name: 'Pilot',
        kind: MediaKind.episode,
        seriesId: 'series-a',
        seriesName: 'Example Show',
        date: DateTime.utc(2026, 6, 10, 20),
        runtimeMinutes: 45,
        genres: const ['Science Fiction', 'Drama'],
        people: const [PersonCredit(name: 'Ada Star', type: 'Actor')],
      ),
      _entry(
        id: 'episode-2',
        name: 'Finale',
        kind: MediaKind.episode,
        seriesId: 'series-a',
        seriesName: 'Example Show',
        date: DateTime.utc(2026, 6, 10, 20, 45),
        runtimeMinutes: 45,
        genres: const ['Science Fiction', 'Drama'],
        people: const [PersonCredit(name: 'Ada Star', type: 'Actor')],
      ),
      _entry(
        id: 'other-year',
        name: 'Old Movie',
        kind: MediaKind.movie,
        date: DateTime.utc(2025, 12, 31),
      ),
    ];

    final summary = YearReviewSummary.fromEntries(entries, 2026);

    expect(summary.entries, hasLength(3));
    expect(summary.moviesWatched, 1);
    expect(summary.episodesWatched, 2);
    expect(summary.uniqueSeries, 1);
    expect(summary.totalDaysActive, 2);
    expect(summary.topSeries?.name, 'Example Show');
    expect(summary.topSeries?.episodeCount, 2);
    expect(summary.busiestMonth, DateTime.june);
    final expectedLocalTime = DateTime.utc(2026, 6, 10, 20).toLocal();
    expect(summary.busiestWeekday, expectedLocalTime.weekday);
    expect(summary.busiestHour, expectedLocalTime.hour);
    expect(summary.weekdayActivity[expectedLocalTime.weekday - 1], 2);
    expect(summary.hourlyActivity[expectedLocalTime.hour], 2);
    expect(summary.monthlyActivity[DateTime.june - 1], 2);
    expect(summary.firstWatched?.id, 'movie-1');
    expect(summary.lastWatched?.id, 'episode-2');
    expect(summary.estimatedWatchTime, const Duration(hours: 3));
    expect(summary.topGenres.first.name, 'Science Fiction');
    expect(summary.topGenres.first.count, 3);
    expect(summary.starPower?.person.name, 'Ada Star');
    expect(summary.starPower?.entries, hasLength(2));
    expect(summary.monthlyMovies[DateTime.january - 1], 1);
    expect(summary.monthlyEpisodes[DateTime.june - 1], 2);
  });

  test('seasonal promo uses the completed year in January', () {
    expect(shouldShowYearReviewPromo(DateTime(2026, 1, 3)), isTrue);
    expect(featuredYearReviewYear(DateTime(2026, 1, 3)), 2025);
    expect(shouldShowYearReviewPromo(DateTime(2026, 12, 3)), isTrue);
    expect(featuredYearReviewYear(DateTime(2026, 12, 3)), 2026);
    expect(shouldShowYearReviewPromo(DateTime(2026, 6, 3)), isFalse);
  });
}

WatchHistoryEntry _entry({
  required String id,
  required String name,
  required MediaKind kind,
  required DateTime date,
  String? seriesId,
  String? seriesName,
  int? runtimeMinutes,
  List<String> genres = const [],
  List<PersonCredit> people = const [],
}) {
  return WatchHistoryEntry(
    id: id,
    name: name,
    kind: kind,
    watchedAt: date,
    seriesId: seriesId,
    seriesName: seriesName,
    runTimeTicks: runtimeMinutes == null
        ? null
        : Duration(minutes: runtimeMinutes).inMicroseconds * 10,
    genres: genres,
    people: people,
  );
}
