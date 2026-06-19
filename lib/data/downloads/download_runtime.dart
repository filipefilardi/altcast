import 'package:background_downloader/background_downloader.dart';

import 'package:altcast/app/router.dart';

class DownloadRuntime {
  DownloadRuntime._();

  static Future<void>? _initialization;

  static Future<void> initialize() {
    return _initialization ??= _initializeWithReset();
  }

  static Future<void> _initializeWithReset() async {
    try {
      await _initialize();
    } catch (error, stackTrace) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _initialize() async {
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
  }

  static Future<bool> requestNotificationPermissions() async {
    await initialize();
    final permissions = FileDownloader().permissions;
    final status = await permissions.status(PermissionType.notifications);
    if (status == PermissionStatus.granted) return true;
    return await permissions.request(PermissionType.notifications) ==
        PermissionStatus.granted;
  }

  static Future<void> configureTaskNotifications(DownloadTask task) async {
    await initialize();
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
