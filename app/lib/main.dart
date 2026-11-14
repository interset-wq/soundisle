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
import 'core/player_controller.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.soundisle.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
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
    if (state == AppLifecycleState.detached) {
      unawaited(BackendService.instance.stop());
    }
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
      final api = ApiClient(baseUrl: handle.baseUrl, token: handle.token);
      final appState = AppState(api);
      await appState.initialize();
      final player = PlayerController(api);
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
    final theme = AppTheme.dark();
    if (_loading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const _SplashScreen(),
      );
    }
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: _ErrorScreen(message: _error!, onRetry: _boot),
      );
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
            Text('正在启动音乐核心…', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.42))),
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
                  style: TextStyle(fontSize: 12, height: 1.6, color: Colors.white.withValues(alpha: 0.5)),
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
