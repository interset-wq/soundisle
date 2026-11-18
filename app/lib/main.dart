import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/backend.dart';
import 'core/permissions.dart';
import 'core/player_controller.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.soundisle.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '播放控制与当前歌曲信息',
      // Adaptive launcher icons are invalid as notification small icons on
      // some Android builds; use the dedicated monochrome drawable instead.
      androidNotificationIcon: 'drawable/ic_stat_soundisle',
      // Keep the media notification (and its controls) in the shade while a
      // track is loaded, including while paused, and make it ongoing so it is
      // not dismissed by a stray swipe. audio_service adds a stop button that
      // removes it when the user really wants it gone.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    );
  }
  if (Platform.isLinux || Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  }

  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> with WidgetsBindingObserver {
  ApiClient? _api;
  AppState? _appState;
  PlayerController? _player;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    // audio_service keeps its Flutter engine and the foreground service alive
    // after the task is removed, but the audio itself is streamed by the local
    // Go core. Stopping that server here would cut background playback and
    // remove the media notification, so keep it running while a track is loaded
    // (playing or paused). With no track loaded the process is free to go.
    final player = _player;
    if (player != null && player.hasSong) return;
    unawaited(BackendService.instance.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.dispose();
    _appState?.dispose();
    _api?.close();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final handle = await BackendService.instance.start();
      unawaited(AppPermissions.requestStartupPermissions());
      final api = ApiClient(baseUrl: handle.baseUrl, token: handle.token);
      final appState = AppState(api);
      await appState.initialize();
      final player = PlayerController(api);
      player.onSongStarted = appState.recordPlayed;
      if (!mounted) {
        player.dispose();
        api.close();
        return;
      }
      setState(() {
        _api = api;
        _appState = appState;
        _player = player;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The stored theme lives in the backend settings and is only available
    // after boot, so the splash follows the system brightness to avoid a
    // jarring flash for users who picked light mode.
    Widget splashApp(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: home,
    );
    if (_loading) {
      return splashApp(const _SplashScreen());
    }
    if (_error != null) {
      return splashApp(_ErrorScreen(message: _error!, onRetry: _boot));
    }
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api!),
        ChangeNotifierProvider<AppState>.value(value: _appState!),
        ChangeNotifierProvider<PlayerController>.value(value: _player!),
      ],
      child: const MusicApp(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentAlt]),
                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 16))],
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 26),
            const Text('声屿', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 10),
            Text('正在启动音乐核心…', style: TextStyle(fontSize: 12, color: context.neutral(0.42))),
            const SizedBox(height: 26),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.error_outline_rounded, size: 34, color: Colors.redAccent),
                ),
                const SizedBox(height: 20),
                const Text('音乐核心启动失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.6, color: context.neutral(0.5)),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
