import 'package:altcast/features/player/playback_resume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int ticks(int minutes) => Duration(minutes: minutes).inMicroseconds * 10;

  test(
    'Home resume uses offline progress instead of stale server progress',
    () {
      expect(
        resolvePlaybackResumePosition(
          resumeTicks: ticks(5),
          localTicks: ticks(12),
        ),
        const Duration(minutes: 12),
      );
    },
  );

  test('resuming after rewinding offline keeps the lower local position', () {
    expect(
      resolvePlaybackResumePosition(
        resumeTicks: ticks(12),
        localTicks: ticks(5),
      ),
      const Duration(minutes: 5),
    );
  });

  test('Downloads resume works without a server position', () {
    expect(
      resolvePlaybackResumePosition(localTicks: ticks(12)),
      const Duration(minutes: 12),
    );
  });

  test('Play from beginning overrides saved offline progress', () {
    expect(
      resolvePlaybackResumePosition(resumeTicks: 0, localTicks: ticks(12)),
      Duration.zero,
    );
  });

  test('explicit remote playback position overrides offline progress', () {
    expect(
      resolvePlaybackResumePosition(
        startTicks: ticks(3),
        localTicks: ticks(12),
      ),
      const Duration(minutes: 3),
    );
    expect(
      resolvePlaybackResumePosition(startTicks: 0, localTicks: ticks(12)),
      Duration.zero,
    );
  });

  test(
    'completed local playback does not fall back to stale server progress',
    () {
      expect(
        resolvePlaybackResumePosition(localTicks: 0, resumeTicks: ticks(12)),
        Duration.zero,
      );
    },
  );

  test('streaming and downloads without local history use server progress', () {
    expect(
      resolvePlaybackResumePosition(resumeTicks: ticks(5)),
      const Duration(minutes: 5),
    );
    expect(resolvePlaybackResumePosition(), Duration.zero);
    expect(resolvePlaybackResumePosition(startTicks: -1), Duration.zero);
  });
}
