import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/trickplay.dart';
import 'package:altcast/features/player/player_material_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TrickplayOverlayData preview() => TrickplayOverlayData(
  session: TrickplaySession.offline(
    itemId: 'video',
    manifest: const TrickplayManifest(
      width: 160,
      height: 90,
      tileWidth: 1,
      tileHeight: 1,
      thumbnailCount: 1,
      intervalMs: 1000,
    ),
    tileFilesByIndex: const {},
  ),
  position: Duration.zero,
  totalDuration: const Duration(minutes: 1),
  alignPercent: 0,
);

class CleanupOnDispose extends StatefulWidget {
  const CleanupOnDispose({super.key, required this.cleanup});
  final VoidCallback cleanup;

  @override
  State<CleanupOnDispose> createState() => _CleanupOnDisposeState();
}

class _CleanupOnDisposeState extends State<CleanupOnDispose> {
  @override
  void dispose() {
    widget.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'removing controls clears a surviving preview after tree unlock',
    (tester) async {
      final notifier = TrickplayOverlayNotifier();
      addTearDown(notifier.dispose);
      final oldPreview = preview();
      notifier.value = oldPreview;

      Widget tree(bool controlsVisible) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            if (controlsVisible)
              CleanupOnDispose(
                key: const ValueKey('controls'),
                cleanup: () => notifier.clearAfterFrame(oldPreview),
              ),
            ValueListenableBuilder<TrickplayOverlayData?>(
              key: const ValueKey('overlay'),
              valueListenable: notifier,
              builder: (_, value, _) =>
                  Text(value == null ? 'hidden' : 'preview'),
            ),
          ],
        ),
      );

      await tester.pumpWidget(tree(true));
      expect(find.text('preview'), findsOneWidget);
      await tester.pumpWidget(tree(false));
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(find.text('hidden'), findsOneWidget);
    },
  );

  testWidgets('old controls cannot clear a newer preview', (tester) async {
    final notifier = TrickplayOverlayNotifier();
    addTearDown(notifier.dispose);
    final oldPreview = preview();
    final newPreview = preview();
    notifier.value = oldPreview;
    notifier.clearAfterFrame(oldPreview);
    notifier.value = newPreview;
    await tester.pump();
    expect(notifier.value, same(newPreview));
  });

  testWidgets('pending cleanup tolerates the player notifier being disposed', (
    tester,
  ) async {
    final notifier = TrickplayOverlayNotifier();
    final oldPreview = preview();
    notifier.value = oldPreview;
    notifier.clearAfterFrame(oldPreview);
    notifier.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
    // A descendant may itself be disposed after its parent's notifier.
    notifier.clearAfterFrame(oldPreview);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
