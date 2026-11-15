import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Copies app-private downloads into the shared system music collection.
///
/// The Go core writes files under the app's private data directory, which file
/// managers cannot see. On Android the Kotlin side inserts the file into
/// MediaStore (`Music/声屿`), so it also shows up in other music players.
class StorageBridge {
  StorageBridge._();

  static const MethodChannel _channel = MethodChannel('app.soundisle/storage');

  static bool get supported => Platform.isAndroid;

  /// User-facing confirmation shown right after queueing a download.
  static String get queuedMessage =>
      supported ? '已加入下载队列，完成后会自动保存到系统音乐' : '已加入下载队列';

  /// Returns a human readable location such as `Music/声屿/Artist - Song.mp3`.
  static Future<String?> exportAudio({
    required String path,
    required String fileName,
    String? mimeType,
  }) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('exportAudio', {
        'path': path,
        'fileName': fileName,
        'mimeType': mimeType ?? mimeForPath(path),
      });
    } on PlatformException catch (error) {
      throw StorageException(error.message ?? '保存到系统音乐库失败');
    } on MissingPluginException {
      return null;
    }
  }

  static String mimeForPath(String path) {
    switch (p.extension(path).toLowerCase().replaceFirst('.', '')) {
      case 'flac':
        return 'audio/flac';
      case 'm4a':
      case 'mp4':
      case 'aac':
        return 'audio/mp4';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'wma':
        return 'audio/x-ms-wma';
      default:
        return 'audio/mpeg';
    }
  }
}

class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
