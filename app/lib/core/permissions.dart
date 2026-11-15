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
}
