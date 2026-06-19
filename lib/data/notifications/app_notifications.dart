import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:altcast/app/router.dart';
import 'package:altcast/data/downloads/download_runtime.dart';

class AppNotifications {
  AppNotifications._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize({bool handleLaunchPayload = true}) async {
    if (_initialized) return;
    _initialized = true;

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_altcast'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );
    if (handleLaunchPayload) unawaited(_openInitialPayload());
  }

  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      return await _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }

    if (Platform.isIOS) {
      return await _localNotifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }

    if (Platform.isMacOS) {
      return await _localNotifications
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }

    return true;
  }

  static Future<bool> requestDownloadPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final downloaderAllowed =
          await DownloadRuntime.requestNotificationPermissions();
      if (!Platform.isIOS) return downloaderAllowed;
      final localAllowed = await requestPermissions();
      return localAllowed;
    }

    return requestPermissions();
  }

  static void configureDownloadTaskNotifications(DownloadTask task) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    DownloadRuntime.configureTaskNotifications(task);
  }

  static Future<void> showDownloadComplete({
    required String itemId,
    required String title,
  }) {
    return _showDownloadFallbackNotification(
      itemId: itemId,
      title: '$title is ready offline',
      body: 'Download finished',
      payload: _payload(type: 'download', itemId: itemId),
    );
  }

  static Future<void> showDownloadRunning({
    required String itemId,
    required String title,
  }) {
    return _showDownloadFallbackNotification(
      itemId: itemId,
      title: 'Downloading $title',
      body: 'Download started',
      payload: _payload(type: 'download', itemId: itemId),
    );
  }

  static Future<void> showDownloadPaused({
    required String itemId,
    required String title,
  }) {
    return _showDownloadFallbackNotification(
      itemId: itemId,
      title: '$title download paused',
      body: 'Open AltCast to resume',
      payload: _payload(type: 'download', itemId: itemId),
    );
  }

  static Future<void> showDownloadCanceled({
    required String itemId,
    required String title,
  }) {
    return _showDownloadFallbackNotification(
      itemId: itemId,
      title: '$title download canceled',
      body: 'Download stopped',
      payload: _payload(type: 'download', itemId: itemId),
    );
  }

  static Future<void> showDownloadFailed({
    required String itemId,
    required String title,
    required String message,
  }) {
    return _showDownloadFallbackNotification(
      itemId: itemId,
      title: "Couldn't download $title",
      body: message,
      payload: _payload(type: 'download', itemId: itemId),
    );
  }

  static Future<void> showNewMovie({
    required String itemId,
    required String title,
  }) {
    return _showLocalNotification(
      id: _notificationId('movie:$itemId'),
      title: 'New movie added',
      body: title,
      payload: _payload(type: 'movie', itemId: itemId),
    );
  }

  static Future<void> showNewEpisode({
    required String itemId,
    required String title,
    required String? seriesId,
    required String? seriesName,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final episodeNumberLabel = _episodeNumberLabel(
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final bodyParts = [?episodeNumberLabel, title];
    return _showLocalNotification(
      id: _notificationId('episode:$itemId'),
      title: seriesName == null || seriesName.trim().isEmpty
          ? 'New episode added'
          : 'New episode of $seriesName',
      body: bodyParts.join(' - '),
      payload: _payload(
        type: 'episode',
        itemId: itemId,
        seriesId: seriesId,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
  }

  static Future<void> _showDownloadFallbackNotification({
    required String itemId,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    await _showLocalNotification(
      id: _notificationId(itemId),
      title: title,
      body: body,
      payload: payload,
    );
  }

  static Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'altcast_notifications',
          'AltCast notifications',
          channelDescription: 'Library and download alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static int _notificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return hash;
  }

  static void _handleLocalNotificationTap(NotificationResponse response) {
    openNotificationRoute(response.payload);
  }

  static Future<void> _openInitialPayload() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return;
    openNotificationRoute(details?.notificationResponse?.payload);
  }

  static String _payload({
    required String type,
    required String itemId,
    String? seriesId,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    final cleanSeriesId = seriesId?.trim();
    final payload = <String, Object>{'type': type, 'itemId': itemId};
    if (cleanSeriesId != null && cleanSeriesId.isNotEmpty) {
      payload['seriesId'] = cleanSeriesId;
    }
    if (seasonNumber != null) payload['seasonNumber'] = seasonNumber;
    if (episodeNumber != null) payload['episodeNumber'] = episodeNumber;
    return jsonEncode(payload);
  }

  static String? _episodeNumberLabel({
    required int? seasonNumber,
    required int? episodeNumber,
  }) {
    if (seasonNumber == null || episodeNumber == null) return null;
    return 'S$seasonNumber E${episodeNumber.toString().padLeft(2, '0')}';
  }
}
