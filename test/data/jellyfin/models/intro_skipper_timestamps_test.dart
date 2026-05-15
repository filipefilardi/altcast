import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/models/intro_skipper_timestamps.dart';

void main() {
  group('IntroSkipperTimestamps.fromPluginTimestampsJson (modern schema)', () {
    test('parses Introduction and Credits, in seconds', () {
      final ts = IntroSkipperTimestamps.fromPluginTimestampsJson(const {
        'Introduction': {'Start': 0, 'End': 30},
        'Credits': {'Start': 1500.5, 'End': 1530},
      });
      expect(ts.introduction!.start, Duration.zero);
      expect(ts.introduction!.end, const Duration(seconds: 30));
      expect(ts.credits!.start, const Duration(milliseconds: 1500500));
      expect(ts.credits!.end, const Duration(seconds: 1530));
      expect(ts.hasAny, isTrue);
    });

    test('accepts lower-case keys (forks vary)', () {
      final ts = IntroSkipperTimestamps.fromPluginTimestampsJson(const {
        'introduction': {'start': 5, 'end': 35},
      });
      expect(ts.introduction!.start, const Duration(seconds: 5));
    });

    test('treats Outro/outro as an alias for Credits', () {
      final ts = IntroSkipperTimestamps.fromPluginTimestampsJson(const {
        'Outro': {'Start': 100, 'End': 130},
      });
      expect(ts.credits, isNotNull);
      expect(ts.credits!.start, const Duration(seconds: 100));
    });

    test('parses numeric strings (some forks emit "12.5")', () {
      final ts = IntroSkipperTimestamps.fromPluginTimestampsJson(const {
        'Introduction': {'Start': '5', 'End': '35.5'},
      });
      expect(ts.introduction!.start, const Duration(seconds: 5));
      expect(ts.introduction!.end, const Duration(milliseconds: 35500));
    });

    test('rejects end <= start, end == 0, and negative values', () {
      expect(
        IntroSkipperTimestamps.fromPluginTimestampsJson(const {
          'Introduction': {'Start': 10, 'End': 10},
        }).introduction,
        isNull,
      );
      expect(
        IntroSkipperTimestamps.fromPluginTimestampsJson(const {
          'Introduction': {'Start': 30, 'End': 10},
        }).introduction,
        isNull,
      );
      expect(
        IntroSkipperTimestamps.fromPluginTimestampsJson(const {
          'Introduction': {'Start': 0, 'End': 0},
        }).introduction,
        isNull,
      );
      expect(
        IntroSkipperTimestamps.fromPluginTimestampsJson(const {
          'Introduction': {'Start': -1, 'End': 10},
        }).introduction,
        isNull,
      );
    });

    test('empty payload returns hasAny == false', () {
      final ts = IntroSkipperTimestamps.fromPluginTimestampsJson(const {});
      expect(ts.introduction, isNull);
      expect(ts.credits, isNull);
      expect(ts.hasAny, isFalse);
    });
  });

  group('IntroSkipperTimestamps.fromLegacyIntroV1Json', () {
    test('parses IntroStart/IntroEnd into the introduction range', () {
      final ts = IntroSkipperTimestamps.fromLegacyIntroV1Json(const {
        'IntroStart': 0,
        'IntroEnd': 42.5,
      });
      expect(ts.introduction!.start, Duration.zero);
      expect(ts.introduction!.end, const Duration(milliseconds: 42500));
      expect(ts.credits, isNull);
    });

    test('drops invalid ranges to an empty result rather than throwing', () {
      expect(
        IntroSkipperTimestamps.fromLegacyIntroV1Json(const {
          'IntroStart': 30,
          'IntroEnd': 10,
        }).hasAny,
        isFalse,
      );
      expect(
        IntroSkipperTimestamps.fromLegacyIntroV1Json(const {
          'IntroStart': 0,
          'IntroEnd': 0,
        }).hasAny,
        isFalse,
      );
      expect(
        IntroSkipperTimestamps.fromLegacyIntroV1Json(const {}).hasAny,
        isFalse,
      );
    });
  });

  group('IntroSkipperRange.contains', () {
    final range = const IntroSkipperRange(
      start: Duration(seconds: 10),
      end: Duration(seconds: 30),
    );

    test('inclusive at start, exclusive at end', () {
      expect(range.contains(const Duration(seconds: 10)), isTrue);
      expect(range.contains(const Duration(seconds: 20)), isTrue);
      expect(range.contains(const Duration(seconds: 30)), isFalse);
      expect(range.contains(const Duration(seconds: 31)), isFalse);
      expect(range.contains(const Duration(seconds: 9)), isFalse);
    });
  });

  group('IntroSkipperTimestamps.mergePreferNonNull', () {
    test('fills gaps from "other" without overwriting present fields', () {
      const primary = IntroSkipperTimestamps(
        introduction: IntroSkipperRange(
          start: Duration.zero,
          end: Duration(seconds: 30),
        ),
      );
      const fallback = IntroSkipperTimestamps(
        introduction: IntroSkipperRange(
          start: Duration(seconds: 5),
          end: Duration(seconds: 40),
        ),
        credits: IntroSkipperRange(
          start: Duration(seconds: 1500),
          end: Duration(seconds: 1530),
        ),
      );

      final merged = primary.mergePreferNonNull(fallback);
      // Primary's introduction wins (non-null), fallback's credits fills in.
      expect(merged.introduction!.start, Duration.zero);
      expect(merged.introduction!.end, const Duration(seconds: 30));
      expect(merged.credits!.start, const Duration(seconds: 1500));
    });
  });
}
