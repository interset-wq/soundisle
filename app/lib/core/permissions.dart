import 'dart:io';

import 'package:flutter/services.dart';

/// Asks the Android shell for permissions that cannot be declared only in the
/// manifest: notification permission (Android 13+) and legacy storage write
/// access (Android 9 and older, used when exporting downloads).
class AppPermissions {
  AppPermissions._();

  static const MethodChannel _channel = MethodChannel('app.soundisle/permissions');

  static Future<void> requestStartupPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('requestStartupPermissions');
    } catch (_) {
      // Denying permissions must never block app startup.
    }
  }

  /// Whether the media notification can currently be displayed.
  ///
  /// Returns null on non-Android platforms or when the shell does not answer.
  static Future<NotificationStatus?> notificationStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('notificationStatus');
      if (raw == null) return null;
      return NotificationStatus(
        enabled: raw['granted'] == true,
        permissionGranted: raw['permissionGranted'] == true,
        appEnabled: raw['appEnabled'] == true,
        channelExists: raw['channelExists'] == true,
        channelImportance: (raw['channelImportance'] as num?)?.toInt() ?? -1,
        activeNotifications: (raw['activeNotifications'] as num?)?.toInt() ?? 0,
        mediaNotificationActive: raw['mediaNotificationActive'] == true,
        channelEnabled: raw['channelEnabled'] != false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Asks for the notification permission again. Android only shows the
  /// dialog while the user has not permanently denied it, so this is safe to
  /// call whenever playback starts.
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } catch (_) {}
  }

  /// Posts a plain test notification, bypassing the media session, so the user
  /// can tell whether notifications work on this device at all.
  static Future<String> sendTestNotification() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('sendTestNotification');
      if (raw == null) return 'unsupported';
      if (raw['posted'] == true) return 'posted';
      return '${raw['reason'] ?? 'failed'}';
    } catch (_) {
      return 'failed';
    }
  }

  static Future<void> openChannelSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openChannelSettings');
    } catch (_) {}
  }

  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openNotificationSettings');
    } catch (_) {}
  }
}

class NotificationStatus {
  const NotificationStatus({
    required this.enabled,
    required this.permissionGranted,
    required this.appEnabled,
    required this.channelExists,
    required this.channelImportance,
    this.activeNotifications = 0,
    this.mediaNotificationActive = false,
    this.channelEnabled = true,
  });

  final bool enabled;
  final bool permissionGranted;
  final bool appEnabled;
  final bool channelExists;
  final int channelImportance;
  final int activeNotifications;

  /// Whether the media notification itself (id 1124) is currently posted.
  final bool mediaNotificationActive;

  /// Whether the media channel is allowed by the system.
  final bool channelEnabled;

  String get label {
    if (!permissionGranted) return '未授权 · 点按去开启';
    if (!appEnabled) return '系统已关闭通知 · 点按去开启';
    if (!channelExists) return '已授权 · 播放后创建通知';
    if (!channelEnabled || channelImportance <= 0) return '媒体通知渠道已关闭 · 点按去开启';
    if (mediaNotificationActive) return '已启用 · 媒体通知已显示';
    if (activeNotifications > 0) return '已启用 · 有其他通知在途';
    return '已启用 · 播放后显示';
  }
}
