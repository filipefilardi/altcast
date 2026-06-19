import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/local/notification_preferences.dart';
import 'package:altcast/data/local/secure_storage.dart';
import 'package:altcast/data/notifications/app_notifications.dart';
import 'package:altcast/data/notifications/library_notification_monitor.dart';

const libraryNotificationBackgroundTaskIdentifier =
    'com.silentsummit.altcast.library-refresh';

const _lastBackgroundCheckKey = 'library_notification_last_background_check_v1';

class LibraryNotificationScheduler {
  LibraryNotificationScheduler._();

  static bool _initialized = false;
  static bool? _lastConfiguredEnabled;
  static LibraryCheckInterval? _lastConfiguredInterval;
  static bool? _requestedEnabled;
  static LibraryCheckInterval? _requestedInterval;
  static Future<void> _configurationQueue = Future<void>.value();

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    try {
      await Workmanager().initialize(_libraryNotificationCallbackDispatcher);
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('Library notification scheduler failed to initialize: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> configure(NotificationPreferences prefs) async {
    if (!isSupported) return;

    final enabled = prefs.shouldCheckLibraryInBackground;
    final interval = prefs.libraryCheckInterval;
    if (_requestedEnabled == enabled && _requestedInterval == interval) {
      return _configurationQueue;
    }

    _requestedEnabled = enabled;
    _requestedInterval = interval;
    _configurationQueue = _configurationQueue.then((_) => _applyRequested());
    return _configurationQueue;
  }

  static Future<void> _applyRequested() async {
    final enabled = _requestedEnabled;
    final interval = _requestedInterval;
    if (enabled == null || interval == null) return;
    if (_lastConfiguredEnabled == enabled &&
        _lastConfiguredInterval == interval) {
      return;
    }

    try {
      await initialize();
      if (!_initialized) return;

      if (!enabled) {
        await Workmanager().cancelByUniqueName(
          libraryNotificationBackgroundTaskIdentifier,
        );
      } else {
        final frequency = interval.duration;
        await Workmanager().registerPeriodicTask(
          libraryNotificationBackgroundTaskIdentifier,
          libraryNotificationBackgroundTaskIdentifier,
          frequency: frequency,
          initialDelay: frequency,
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      }

      _lastConfiguredEnabled = enabled;
      _lastConfiguredInterval = interval;
      debugPrint(
        'Library notification schedule configured: '
        '${enabled ? interval.label : 'Off'}',
      );
    } catch (error, stackTrace) {
      debugPrint('Library notification scheduler failed to configure: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> runBackgroundTask(String taskName) async {
    if (taskName != libraryNotificationBackgroundTaskIdentifier &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    if (!isSupported) return true;

    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final container = ProviderContainer();
    try {
      await AppNotifications.initialize(handleLaunchPayload: false);

      final storage = container.read(secureStorageProvider);
      final prefs = await NotificationPreferences.load(storage);
      if (!prefs.shouldCheckLibraryInBackground) {
        debugPrint('Library notification check skipped: disabled');
        return true;
      }
      if (!await _isDue(storage, prefs.libraryCheckInterval)) {
        debugPrint('Library notification check skipped: interval not due');
        return true;
      }

      final session = await container.read(authRepositoryProvider).restore();
      if (session == null) {
        debugPrint('Library notification check skipped: no saved session');
        return true;
      }

      debugPrint('Library notification check started');
      await container
          .read(libraryNotificationMonitorProvider.notifier)
          .checkForUpdates(force: true, preferences: prefs, session: session);
      await _markChecked(storage);
      debugPrint('Library notification check completed');
    } catch (error, stackTrace) {
      debugPrint('Library notification background check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      container.dispose();
    }

    return true;
  }

  static Future<bool> _isDue(
    SecureStorage storage,
    LibraryCheckInterval interval,
  ) async {
    final duration = interval.duration;

    final raw = await storage.read(_lastBackgroundCheckKey);
    final lastCheck = raw == null ? null : DateTime.tryParse(raw);
    if (lastCheck == null) return true;
    return DateTime.now().toUtc().difference(lastCheck.toUtc()) >= duration;
  }

  static Future<void> _markChecked(SecureStorage storage) {
    return storage.write(
      _lastBackgroundCheckKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

@pragma('vm:entry-point')
void _libraryNotificationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) {
    return LibraryNotificationScheduler.runBackgroundTask(taskName);
  });
}
