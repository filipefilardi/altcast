import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/seerr/models.dart';
import 'package:altcast/data/seerr/seerr_repository.dart';
import 'package:altcast/features/requests/requests_screen.dart';
import 'package:altcast/features/search/seerr_discover_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Connected extends SeerrConnectionNotifier {
  @override
  Future<SeerrSession?> build() async => const SeerrSession(
    serverUrl: 'https://example.test',
    username: 'Viewer',
    cookieHeader: 'session=test',
  );
}

class _FailedRetry extends Fake implements SeerrRepository {
  int? retriedId;

  @override
  Future<void> retryRequest(int requestId) async {
    retriedId = requestId;
    throw const SeerrException('Seerr is offline.');
  }
}

void main() {
  testWidgets(
    'active rows reserve the date, hide missing causes and show measured progress',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const longTitle =
          'A very long series title that cannot fit beside the request date';
      final repo = _FailedRetry();
      final requests = [
        SeerrRequest.fromJson({
          'id': 1,
          'type': 'tv',
          'status': 4,
          'media': {'title': longTitle, 'status': 3},
          'createdAt': '2026-11-17T12:00:00',
          'requestedBy': {'displayName': 'pirao'},
          'failureReason': '   ',
        }),
        SeerrRequest.fromJson({
          'id': 2,
          'type': 'tv',
          'status': 4,
          'media': {'title': 'Another show'},
          'failureReason': 'Sonarr is unavailable.',
        }),
        SeerrRequest.fromJson({
          'id': 3,
          'type': 'movie',
          'status': 2,
          'media': {
            'title': 'Downloading movie',
            'status': 3,
            'downloadStatus': [
              {'size': 100, 'sizeLeft': 25, 'timeLeft': '01:03:50'},
            ],
          },
        }),
        SeerrRequest.fromJson({
          'id': 4,
          'type': 'movie',
          'status': 2,
          'media': {
            'title': 'Waiting movie',
            'status': 3,
            'downloadStatus': [
              {'size': 100},
            ],
          },
        }),
        SeerrRequest.fromJson({
          'id': 5,
          'type': 'movie',
          'status': 2,
          'media': {'title': 'Ready movie', 'status': 5},
        }),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrRepositoryProvider.overrideWithValue(repo),
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => requests),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text(longTitle);
      final date = find.text('Nov 17');
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.getRect(title).right, lessThan(tester.getRect(date).left));
      expect(
        tester
            .getRect(title)
            .contains(
              Offset(tester.getCenter(title).dx, tester.getCenter(date).dy),
            ),
        isTrue,
      );
      expect(find.text('Retry'), findsNWidgets(2));
      expect(find.text('Sonarr is unavailable.'), findsOneWidget);
      expect(find.textContaining('No failure details'), findsNothing);
      expect(find.text('In download queue'), findsOneWidget);
      expect(find.text('Processing'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('1h 4m left'), findsOneWidget);
      expect(find.text('100 B total'), findsNWidgets(2));
      expect(find.textContaining('75 B of'), findsNothing);
      final downloadLabel = find.descendant(
        of: find.byKey(const ValueKey(3)),
        matching: find.text('Downloading'),
      );
      expect(downloadLabel, findsOneWidget);
      await tester.tap(downloadLabel);
      await tester.pumpAndSettle();
      expect(find.text('75%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('1h 4m left'), findsNothing);
      await tester.tap(downloadLabel);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Ready movie'), findsNothing);
      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();
      expect(repo.retriedId, 1);
      expect(find.text('Retry failed: Seerr is offline.'), findsOneWidget);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Ready movie'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
  testWidgets(
    'a long failed queue previews the newest three and expands inline',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = [
        for (var day = 1; day <= 13; day++)
          SeerrRequest(
            id: day,
            mediaType: SeerrMediaType.tv,
            status: SeerrRequestStatus.failed,
            title: 'Show $day',
            createdAt: DateTime(2026, 11, day),
            seasons: const [1],
            requestedByName: 'pirao',
          ),
        const SeerrRequest(
          id: 14,
          mediaType: SeerrMediaType.movie,
          status: SeerrRequestStatus.approved,
          title: 'In progress',
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => requests),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNWidgets(3));
      expect(find.text('Show 13'), findsOneWidget);
      expect(find.text('Show 11'), findsOneWidget);
      expect(find.text('Show 10'), findsNothing);
      final first = find.byKey(const ValueKey(13));
      final second = find.byKey(const ValueKey(12));
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      final row = tester.getRect(first);
      final retry = tester.getRect(
        find.descendant(of: first, matching: find.text('Retry')),
      );
      final requester = tester.getRect(
        find.descendant(of: first, matching: find.text('pirao')),
      );
      expect(retry.center.dx, greaterThan(requester.left));
      expect(retry.top, lessThan(requester.bottom));
      expect(row.height, lessThan(120));
      expect(find.text('In progress').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Show all 13 failed requests'));
      await tester.pumpAndSettle();
      expect(find.text('Show 10'), findsOneWidget);
      final list = find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Show fewer'),
        350,
        scrollable: list,
      );
      expect(find.text('Show 1'), findsOneWidget);
      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();
      expect(find.text('Show all 13 failed requests'), findsOneWidget);
      expect(find.text('Show 1'), findsNothing);
    },
  );
  testWidgets(
    'downloads stay above both independent, expandable previews as the queue refreshes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 4000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = [
        for (var i = 1; i <= 4; i++)
          SeerrRequest(
            id: i,
            mediaType: SeerrMediaType.tv,
            status: SeerrRequestStatus.failed,
            title: 'Failure $i',
          ),
        for (var i = 1; i <= 5; i++)
          SeerrRequest(
            id: 10 + i,
            mediaType: SeerrMediaType.movie,
            status: SeerrRequestStatus.approved,
            title: 'Queued $i',
            createdAt: DateTime(2026, 11, i),
          ),
        for (var i = 1; i <= 4; i++)
          SeerrRequest.fromJson({
            'id': 20 + i,
            'type': 'movie',
            'status': 2,
            'media': {
              'title': 'Transfer $i',
              'status': 3,
              'downloadStatus': [
                if (i.isEven)
                  {'size': 100, 'sizeLeft': 35}
                else
                  {'status': 'downloading'},
              ],
            },
          }),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => [...requests]),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final waitingToggle = find.text('Show all 5 waiting requests');
      final failedToggle = find.text('Show all 4 failed requests');
      for (final toggle in [waitingToggle, failedToggle]) {
        expect(
          find.ancestor(of: toggle, matching: find.byType(DecoratedSliver)),
          findsOneWidget,
        );
      }
      expect(find.text('Queued 2'), findsNothing);
      expect(find.text('Queued 3'), findsOneWidget);
      expect(find.text('Failure 1'), findsNothing);
      final downloadsToggle = find.text('Show all 4 downloads');
      expect(find.text('Transfer 1'), findsNothing);
      await tester.tap(downloadsToggle);
      await tester.pumpAndSettle();
      for (var i = 1; i <= 4; i++) {
        expect(
          tester.getCenter(find.text('Transfer $i')).dy,
          lessThan(tester.getCenter(find.text('Failed requests')).dy),
        );
      }
      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();
      expect(downloadsToggle, findsOneWidget);
      await tester.tap(waitingToggle);
      await tester.pumpAndSettle();
      expect(find.text('Queued 1'), findsOneWidget);
      expect(failedToggle, findsOneWidget);
      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();
      await tester.tap(failedToggle);
      await tester.pumpAndSettle();
      expect(find.text('Failure 1'), findsOneWidget);
      expect(waitingToggle, findsOneWidget);

      final idx = requests.indexWhere((r) => r.title == 'Queued 1');
      requests[idx] = requests[idx].copyWith(
        downloads: const [
          SeerrDownloadStatus(
            size: 0,
            sizeLeft: null,
            status: 'queued',
            timeLeft: '',
            title: '',
          ),
        ],
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Show all 5 downloads'), findsOneWidget);
      expect(find.text('Queued 1'), findsNothing);
      await tester.tap(find.text('Show all 5 downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Queued 1'), findsOneWidget);
      expect(find.text('In download queue'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Queued 1')).dy,
        lessThan(tester.getCenter(find.text('Failed requests')).dy),
      );
      expect(find.text('Show all 4 waiting requests'), findsOneWidget);
      expect(find.text('Queued 2'), findsNothing);
      expect(find.text('Failure 1'), findsOneWidget);
    },
  );
  testWidgets(
    'series progress covers the reported queue and omits an individual transfer ETA',
    (tester) async {
      final request = SeerrRequest.fromJson({
        'id': 91,
        'status': 2,
        'type': 'tv',
        'seasons': [
          {'seasonNumber': 2},
        ],
        'media': {
          'title': 'Series in progress',
          'status': 4,
          'downloadStatus': [
            {
              'episode': {'seasonNumber': 2, 'episodeNumber': 1},
              'downloadId': 'season-pack',
              'size': 900,
              'sizeLeft': 900,
              'timeLeft': '5 min',
              'status': 'downloading',
            },
            {
              'episode': {'seasonNumber': 2, 'episodeNumber': 2},
              'downloadId': 'season-pack',
              'size': 900,
              'sizeLeft': 900,
              'status': 'downloading',
            },
            {
              'episode': {'seasonNumber': 3},
              'downloadId': 'another-season',
              'size': 500,
              'sizeLeft': 20,
            },
            {'size': 100, 'sizeLeft': 0, 'status': 'completed'},
          ],
        },
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => [request]),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
      expect(find.text('2 reported downloads'), findsOneWidget);
      expect(find.textContaining('Partially available'), findsOneWidget);
      expect(find.text('1000 B total'), findsOneWidget);
      expect(find.textContaining('ETA'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .1,
      );
    },
  );
  testWidgets(
    'series with incomplete telemetry scopes its bar to reporting transfers',
    (tester) async {
      final requests = [
        for (final withData in [true, false])
          SeerrRequest.fromJson({
            'id': withData ? 95 : 96,
            'type': 'tv',
            'status': 2,
            'media': {
              'status': 3,
              'title': withData ? 'Some sizes' : 'No sizes',
              'downloadStatus': [
                if (withData) ...[
                  {'size': 100, 'sizeLeft': 0},
                  {'size': 300, 'sizeLeft': 100},
                ],
                if (withData) ...[
                  {'size': 0, 'status': 'downloading'},
                  {'size': 200},
                ] else
                  for (var episode = 1; episode <= 10; episode++)
                    {
                      'size': 0,
                      'sizeLeft': 0,
                      'status': 'queued',
                      'downloadId': 'transfer-$episode',
                    },
              ],
            },
          }),
      ];
      expect(requests.first.progress, isNull);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => requests),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Progress for 2 of 4 reported downloads'),
        findsOneWidget,
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('Waiting for byte counts'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
      final queued = find.byKey(const ValueKey(96));
      expect(
        find.descendant(of: queued, matching: find.text('In download queue')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: queued,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
      final first = find.byKey(const ValueKey(95));
      await tester.tap(
        find.descendant(of: first, matching: find.text('Downloading')),
      );
      await tester.pumpAndSettle();
      expect(find.text('75%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
  testWidgets(
    'poster-only requests resolve a landscape backdrop from Seerr details',
    (tester) async {
      final request = SeerrRequest.fromJson({
        'id': 1,
        'type': 'tv',
        'status': 2,
        'media': {
          'status': 3,
          'tmdbId': 42,
          'name': 'Better Call Saul',
          'posterPath': '/portrait.jpg',
        },
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            seerrConnectionProvider.overrideWith(_Connected.new),
            seerrRequestsProvider.overrideWith((_) async => [request]),
            seerrDetailsProvider.overrideWith(
              (ref, key) async => SeerrMediaDetails(
                id: key.id,
                mediaType: key.mediaType,
                title: 'Better Call Saul',
                backdropPath: '/landscape.jpg',
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const RequestsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final artwork = find.byType(LocalOrNetworkImage);
      expect(
        tester.widget<LocalOrNetworkImage>(artwork).source,
        'https://image.tmdb.org/t/p/w780/landscape.jpg',
      );
      expect(
        tester.getSize(artwork).width,
        greaterThan(tester.getSize(artwork).height),
      );
      expect(find.text('Better Call Saul'), findsOneWidget);
    },
  );
}
