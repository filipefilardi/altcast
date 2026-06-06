import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';

const _titleSubtitlePrefsKey = 'title_subtitle_preferences_v1';

enum TitleSubtitleMode { serverDefault, off, byLanguage }

class TitleSubtitlePreference {
  const TitleSubtitlePreference.serverDefault()
    : mode = TitleSubtitleMode.serverDefault,
      language = null,
      streamIndex = null;

  const TitleSubtitlePreference.off()
    : mode = TitleSubtitleMode.off,
      language = null,
      streamIndex = null;

  const TitleSubtitlePreference.byLanguage({this.language, this.streamIndex})
    : mode = TitleSubtitleMode.byLanguage;

  final TitleSubtitleMode mode;
  final String? language;
  final int? streamIndex;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'language': language,
    'streamIndex': streamIndex,
  };

  factory TitleSubtitlePreference.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    final mode = TitleSubtitleMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => TitleSubtitleMode.off,
    );
    switch (mode) {
      case TitleSubtitleMode.serverDefault:
        return const TitleSubtitlePreference.serverDefault();
      case TitleSubtitleMode.off:
        return const TitleSubtitlePreference.off();
      case TitleSubtitleMode.byLanguage:
        final language = (json['language'] as String?)?.trim();
        final streamIndex = json['streamIndex'] as int?;
        if ((language == null || language.isEmpty) && streamIndex == null) {
          return const TitleSubtitlePreference.off();
        }
        return TitleSubtitlePreference.byLanguage(
          language: language,
          streamIndex: streamIndex,
        );
    }
  }

  @override
  bool operator ==(Object other) {
    return other is TitleSubtitlePreference &&
        other.mode == mode &&
        other.language == language &&
        other.streamIndex == streamIndex;
  }

  @override
  int get hashCode => Object.hash(mode, language, streamIndex);
}

final titleSubtitlePreferencesProvider =
    NotifierProvider<
      TitleSubtitlePreferencesNotifier,
      Map<String, TitleSubtitlePreference>
    >(TitleSubtitlePreferencesNotifier.new);

class TitleSubtitlePreferencesNotifier
    extends Notifier<Map<String, TitleSubtitlePreference>> {
  @override
  Map<String, TitleSubtitlePreference> build() {
    _restore();
    return const {};
  }

  TitleSubtitlePreference? preferenceFor(String itemId) => state[itemId];

  Future<void> followDefault(String itemId) async {
    if (!state.containsKey(itemId)) return;
    final next = Map<String, TitleSubtitlePreference>.of(state)..remove(itemId);
    state = next;
    await _persist();
  }

  Future<void> setPreference(
    String itemId,
    TitleSubtitlePreference preference,
  ) async {
    state = {...state, itemId: preference};
    await _persist();
  }

  Future<void> _restore() async {
    final raw = await ref
        .read(secureStorageProvider)
        .read(_titleSubtitlePrefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final entry in data.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: TitleSubtitlePreference.fromJson(entry.value),
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(
          _titleSubtitlePrefsKey,
          jsonEncode({
            for (final entry in state.entries) entry.key: entry.value.toJson(),
          }),
        );
  }
}
