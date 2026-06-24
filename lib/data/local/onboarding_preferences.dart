import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';

const _onboardingPrefsKey = 'onboarding_preferences_v1';

class OnboardingPreferences {
  const OnboardingPreferences({
    this.hasCompleted = false,
    this.wasSkipped = false,
    this.isRestored = false,
  });

  final bool hasCompleted;
  final bool wasSkipped;
  final bool isRestored;

  OnboardingPreferences copyWith({
    bool? hasCompleted,
    bool? wasSkipped,
    bool? isRestored,
  }) {
    return OnboardingPreferences(
      hasCompleted: hasCompleted ?? this.hasCompleted,
      wasSkipped: wasSkipped ?? this.wasSkipped,
      isRestored: isRestored ?? this.isRestored,
    );
  }

  Map<String, dynamic> toJson() => {
    'hasCompleted': hasCompleted,
    'wasSkipped': wasSkipped,
  };

  factory OnboardingPreferences.fromJson(Map<String, dynamic> json) {
    return OnboardingPreferences(
      hasCompleted: json['hasCompleted'] as bool? ?? false,
      wasSkipped: json['wasSkipped'] as bool? ?? false,
      isRestored: true,
    );
  }

  static Future<OnboardingPreferences> load(SecureStorage storage) async {
    final raw = await storage.read(_onboardingPrefsKey);
    if (raw == null) return const OnboardingPreferences(isRestored: true);
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return OnboardingPreferences.fromJson(data);
    } catch (_) {
      return const OnboardingPreferences(isRestored: true);
    }
  }
}

final onboardingPreferencesProvider =
    NotifierProvider<OnboardingPreferencesNotifier, OnboardingPreferences>(
      OnboardingPreferencesNotifier.new,
    );

class OnboardingPreferencesNotifier extends Notifier<OnboardingPreferences> {
  @override
  OnboardingPreferences build() {
    _restore();
    return const OnboardingPreferences();
  }

  Future<void> _restore() async {
    state = await OnboardingPreferences.load(ref.read(secureStorageProvider));
  }

  Future<void> complete() async {
    state = const OnboardingPreferences(
      hasCompleted: true,
      wasSkipped: false,
      isRestored: true,
    );
    await _persist();
  }

  Future<void> skip() async {
    state = const OnboardingPreferences(
      hasCompleted: true,
      wasSkipped: true,
      isRestored: true,
    );
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_onboardingPrefsKey, jsonEncode(state.toJson()));
  }
}
