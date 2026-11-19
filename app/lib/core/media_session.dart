import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges the Android shell's media-session clean-up helpers.
///
/// `audio_service` keeps its foreground service alive while the activity is
/// bound, so ending playback leaves a stale, non-dismissible media card behind.
/// The shell drops the foreground state explicitly instead; this is a no-op on
/// every other platform.
class MediaSession {
  MediaSession._();

  static const MethodChannel _channel = MethodChannel('app.soundisle/media');

  /// Called when the shell observes the media session becoming inactive, as a
  /// fallback for stops that do not surface as a player state change.
  static Future<void> Function()? onStopped;

  /// Removes the foreground media notification after the session ends.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopSession');
    } catch (_) {}
  }

  /// Watches the media session so a stop from the notification also clears the
  /// notification and lets the app reset its UI.
  ///
  /// Returns false when the foreground service does not exist yet; the service
  /// is created asynchronously after playback starts, so callers retry.
  static Future<bool> watch() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('watchSession') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Installs the method-call handler used by the shell. Call once at startup.
  static void install() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sessionStopped') {
        await onStopped?.call();
      }
      return null;
    });
  }
}
