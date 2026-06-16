import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';

const _notificationPrefsKey = 'notification_preferences_v1';

class NotificationPreferences {
  const NotificationPreferences({this.downloadNotifications = true});

  final bool downloadNotifications;

  NotificationPreferences copyWith({bool? downloadNotifications}) {
    return NotificationPreferences(
      downloadNotifications:
          downloadNotifications ?? this.downloadNotifications,
    );
  }

  Map<String, dynamic> toJson() => {
    'downloadNotifications': downloadNotifications,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      downloadNotifications: json['downloadNotifications'] as bool? ?? true,
    );
  }
}

final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
      NotificationPreferencesNotifier.new,
    );

class NotificationPreferencesNotifier
    extends Notifier<NotificationPreferences> {
  @override
  NotificationPreferences build() {
    _restore();
    return const NotificationPreferences();
  }

  Future<void> _restore() async {
    final raw = await ref
        .read(secureStorageProvider)
        .read(_notificationPrefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = NotificationPreferences.fromJson(data);
    } catch (_) {}
  }

  Future<void> setDownloadNotifications(bool enabled) async {
    state = state.copyWith(downloadNotifications: enabled);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_notificationPrefsKey, jsonEncode(state.toJson()));
  }
}
