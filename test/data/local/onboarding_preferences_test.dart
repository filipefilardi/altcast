import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/local/onboarding_preferences.dart';

void main() {
  group('OnboardingPreferences', () {
    test('defaults to incomplete before restore', () {
      const prefs = OnboardingPreferences();

      expect(prefs.hasCompleted, isFalse);
      expect(prefs.wasSkipped, isFalse);
      expect(prefs.isRestored, isFalse);
    });

    test('serializes completed and skipped state', () {
      const prefs = OnboardingPreferences(
        hasCompleted: true,
        wasSkipped: true,
        isRestored: true,
      );

      final restored = OnboardingPreferences.fromJson(prefs.toJson());

      expect(restored.hasCompleted, isTrue);
      expect(restored.wasSkipped, isTrue);
      expect(restored.isRestored, isTrue);
    });
  });
}
