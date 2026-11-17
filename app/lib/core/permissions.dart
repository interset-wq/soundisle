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
      );
    } catch (_) {
      return null;
    }
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
  });

  final bool enabled;
  final bool permissionGranted;
  final bool appEnabled;
  final bool channelExists;
  final int channelImportance;
  final int activeNotifications;

  String get label {
    if (!permissionGranted) return '未授权 · 点按打开设置';
    if (!appEnabled) return '系统已关闭通知 · 点按打开设置';
    if (!channelExists) return '已授权 · 播放后创建通知';
    if (channelImportance <= 0) return '通知渠道已关闭 · 点按打开设置';
    if (activeNotifications > 0) return '已启用 · 通知已显示';
    return '已启用 · 播放后显示';
  }
}
