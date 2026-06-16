import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';

import 'package:altcast/app/router.dart';

class AppNotifications {
  AppNotifications._();

  static const _macChannel = MethodChannel('altcast/notifications');
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final downloader = FileDownloader();
    await downloader.ready;
    await downloader.configure(
      androidConfig: [
        (Config.runInForeground, true),
        (Config.checkAvailableSpace, 200),
      ],
      iOSConfig: [
        (Config.resourceTimeout, const Duration(hours: 4)),
        (Config.excludeFromCloudBackup, true),
      ],
    );
    downloader.registerCallbacks(
      taskNotificationTapCallback: _handleDownloadNotificationTap,
    );
    await downloader.start(autoCleanDatabase: true);

    if (Platform.isMacOS) {
      _macChannel.setMethodCallHandler(_handleMacNotificationCall);
    }
  }

  static Future<bool> requestPermissions() async {
    if (Platform.isMacOS) {
      try {
        return await _macChannel.invokeMethod<bool>('requestPermission') ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final permissions = FileDownloader().permissions;
      final status = await permissions.status(PermissionType.notifications);
      if (status == PermissionStatus.granted) return true;
      return await permissions.request(PermissionType.notifications) ==
          PermissionStatus.granted;
    }

    return true;
  }

  static void configureDownloadTaskNotifications(DownloadTask task) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    FileDownloader().configureNotificationForTask(
      task,
      running: const TaskNotification(
        'Downloading {displayName}',
        '{progress} complete',
      ),
      complete: const TaskNotification(
        '{displayName} is ready offline',
        'Download finished',
      ),
      error: const TaskNotification(
        "Couldn't download {displayName}",
        'Open AltCast to retry',
      ),
      paused: const TaskNotification(
        '{displayName} download paused',
        'Open AltCast to resume',
      ),
      canceled: const TaskNotification(
        '{displayName} download canceled',
        'Download stopped',
      ),
      progressBar: true,
    );
  }

  static Future<void> showDownloadComplete({
    required String itemId,
    required String title,
  }) {
    return _showMacDownloadNotification(
      itemId: itemId,
      title: '$title is ready offline',
      body: 'Download finished',
    );
  }

  static Future<void> showDownloadFailed({
    required String itemId,
    required String title,
    required String message,
  }) {
    return _showMacDownloadNotification(
      itemId: itemId,
      title: "Couldn't download $title",
      body: message,
    );
  }

  static Future<void> _showMacDownloadNotification({
    required String itemId,
    required String title,
    required String body,
  }) async {
    if (!Platform.isMacOS) return;
    final allowed = await requestPermissions();
    if (!allowed) return;
    await _macChannel.invokeMethod<void>('showNotification', {
      'id': _notificationId(itemId),
      'title': title,
      'body': body,
      'payload': itemId,
    });
  }

  static int _notificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return hash;
  }

  static Future<void> _handleMacNotificationCall(MethodCall call) async {
    if (call.method != 'notificationTapped') return;
    final payload = call.arguments as String?;
    openDownloadNotificationRoute(payload);
  }

  static void _handleDownloadNotificationTap(Task task, NotificationType _) {
    openDownloadNotificationRoute(_downloadItemIdFromTask(task));
  }

  static String? _downloadItemIdFromTask(Task task) {
    final metadata = task.metaData.trim();
    if (metadata.isNotEmpty) return metadata;
    final filename = task.filename;
    const suffix = '.video';
    if (filename.endsWith(suffix)) {
      return filename.substring(0, filename.length - suffix.length);
    }
    return null;
  }
}
