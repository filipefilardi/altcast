import 'package:altcast/data/jellyfin/models/remote_session.dart';
import 'package:altcast/features/player/player_material_theme.dart';
import 'package:altcast/features/remote/remote_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 411.4, 800.0]) {
    testWidgets('primary controls fit a $width pixel player', (tester) async {
      final volume = ValueNotifier(0.5);
      final brightness = ValueNotifier(0.5);
      addTearDown(volume.dispose);
      addTearDown(brightness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeRemoteSessionProvider.overrideWith(
              (ref) => Stream.value(
                const RemoteSession(
                  id: 'remote',
                  deviceId: 'device',
                  deviceName: 'TV',
                  client: 'Test',
                  userId: 'user',
                  userName: 'User',
                  supportsRemoteControl: true,
                  supportedCommands: {},
                  nowPlayingItemId: 'video',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: 400,
                  child: Consumer(
                    builder: (context, ref, _) {
                      // Wait for the remote state to avoid requiring native mpv.
                      if (!ref.watch(activeRemoteSessionProvider).hasValue) {
                        return const SizedBox.shrink();
                      }
                      return AltCastPrimaryControls(
                        volumeLevelListenable: volume,
                        brightnessLevelListenable: brightness,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bounds = tester.getRect(find.byType(AltCastPrimaryControls));
      final back = tester.getRect(find.byTooltip('Back 10 seconds'));
      final play = tester.getRect(find.byTooltip('Pause'));
      final forward = tester.getRect(find.byTooltip('Forward 10 seconds'));
      const tokens = kDefaultPlayerMaterialTokens;
      final inset =
          tokens.gestureIndicatorWidth +
          tokens.gestureIndicatorHorizontalPadding;
      expect(back.left, greaterThanOrEqualTo(bounds.left + inset));
      expect(forward.right, lessThanOrEqualTo(bounds.right - inset));
      expect(back.right, lessThanOrEqualTo(play.left));
      expect(play.right, lessThanOrEqualTo(forward.left));
      for (final rect in [back, play, forward]) {
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
    });
  }
}
