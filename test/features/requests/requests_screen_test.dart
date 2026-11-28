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
              {'size': 100, 'sizeLeft': 25},
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
      expect(find.text('Waiting for queue details'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
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
}
