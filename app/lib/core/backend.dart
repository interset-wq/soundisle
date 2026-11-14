import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackendHandle {
  const BackendHandle({required this.baseUrl, required this.token, required this.dataDir});

  final String baseUrl;
  final String token;
  final String dataDir;
}

/// Starts the embedded Go music core.
///
/// * Android / iOS use a gomobile native library through a method channel.
/// * Desktop platforms start a bundled sidecar process and read its listening
///   port from a single JSON line on stdout.
class BackendService {
  BackendService._();

  static final BackendService instance = BackendService._();
  static const MethodChannel _channel = MethodChannel('app.soundisle/backend');

  Process? _process;
  BackendHandle? _handle;

  BackendHandle? get handle => _handle;

  Future<BackendHandle> start() async {
    if (_handle != null) return _handle!;
    final dataDir = await _resolveDataDir();
    final token = _randomToken();
    if (Platform.isAndroid || Platform.isIOS) {
      final port = await _channel.invokeMethod<int>('start', {
        'dataDir': dataDir,
        'token': token,
      });
      if (port == null || port <= 0) {
        throw StateError('音乐核心启动失败');
      }
      _handle = BackendHandle(baseUrl: 'http://127.0.0.1:$port', token: token, dataDir: dataDir);
      return _handle!;
    }
    final binary = _findDesktopBinary();
    debugPrint('music core: $binary');
    final process = await Process.start(binary, [
      '--addr',
      '127.0.0.1:0',
      '--token',
      token,
      '--data-dir',
      dataDir,
      '--json',
    ]);
    _process = process;
    process.stderr.transform(utf8.decoder).listen((line) {
      if (line.trim().isNotEmpty) debugPrint('core: ${line.trim()}');
    });

    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription<String> sub;
    sub = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (completer.isCompleted || line.trim().isEmpty) return;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map && decoded['port'] is int) {
          completer.complete(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        debugPrint('core stdout: $line');
      }
    });
    process.exitCode.then((code) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('音乐核心已退出 (code $code)'));
      }
    });
    final payload = await completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw StateError('音乐核心启动超时'),
    );
    await sub.cancel();
    final port = payload['port'] as int;
    _handle = BackendHandle(
      baseUrl: 'http://127.0.0.1:$port',
      token: token,
      dataDir: (payload['dataDir'] as String?) ?? dataDir,
    );
    return _handle!;
  }

  Future<String> _resolveDataDir() async {
    final override = Platform.environment['SOUNDISLE_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override).create(recursive: true).then((d) => d.path);
    }
    final dir = await getApplicationSupportDirectory();
    final target = Directory(p.join(dir.path, 'soundisle'));
    await target.create(recursive: true);
    return target.path;
  }

  String _findDesktopBinary() {
    final env = Platform.environment['SOUNDISLE_BACKEND'];
    if (env != null && env.trim().isNotEmpty && File(env).existsSync()) {
      return env;
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'soundisle-core.exe' : 'soundisle-core';
    final candidates = <String>[
      p.join(exeDir, name),
      p.join(exeDir, 'data', 'flutter_assets', name),
      p.join(Directory.current.path, '..', 'backend', 'bin', name),
      p.join(Directory.current.path, 'backend', 'bin', name),
      p.join(Directory.current.path, '..', '..', 'backend', 'bin', name),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    throw StateError(
      '找不到音乐核心：$name\n请先运行 scripts/build_backend.sh，或设置 SOUNDISLE_BACKEND 环境变量。',
    );
  }

  String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> stop() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _channel.invokeMethod('stop');
      } catch (_) {}
    }
    _process?.kill();
    _process = null;
    _handle = null;
  }
}
