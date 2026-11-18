import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  bool _showLyrics = false;
  double? _dragValue;
  final ScrollController _lyricController = ScrollController();
  int _lastLyricIndex = -1;
  bool _draggingLyrics = false;

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final app = context.watch<AppState>();
    final song = player.current;
    if (song == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final cover = app.api.coverUrl(song.cover, source: song.source);
    final screen = MediaQuery.sizeOf(context);
    final artSize = (screen.shortestSide * 0.68).clamp(220.0, 380.0);

    final background = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cover.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Opacity(
                // A lighter wash keeps dark text readable over bright covers.
                opacity: dark ? 0.55 : 0.32,
                child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: 0.4),
                  background.withValues(alpha: 0.8),
                  background,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(context, song, app, player),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 560;
                      final topPadding = compact ? 4.0 : 10.0;
                      final available = constraints.maxHeight - topPadding - 12;
                      // Let the column fill the whole viewport and spread its
                      // sections out, so tall phones do not leave an empty band
                      // at the bottom. Short screens still scroll normally.
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(24, topPadding, 24, 12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: available > 0 ? available : 0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (_showLyrics)
                                SizedBox(
                                  height: compact ? artSize * 0.9 : artSize,
                                  child: _lyricsView(context, player),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: CoverArt(
                                    url: cover,
                                    size: artSize,
                                    radius: 26,
                                    seed: song.name,
                                    heroTag: 'player-cover',
                                  ),
                                ),
                              SizedBox(height: compact ? 12 : 16),
                              _titleRow(context, song, app, player),
                              SizedBox(height: compact ? 8 : 12),
                              _progress(context, player, song),
                              SizedBox(height: compact ? 4 : 8),
                              _controls(context, player),
                              SizedBox(height: compact ? 8 : 12),
                              _bottomActions(context, player, app, song),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (player.loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar(
    BuildContext context,
    Song song,
    AppState app,
    PlayerController player,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '正在播放',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: context.neutral(0.42),
                  ),
                ),
                const SizedBox(height: 3),
                SourceBadge(name: app.sourceName(song.source)),
                if (player.playInfo?.fallback == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    '已自动切换到 ${app.sourceName(player.playInfo!.fallbackSource)}',
                    style: TextStyle(
                      fontSize: 9,
                      color: const Color(0xFF54D68C).withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(Icons.queue_music_rounded, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _titleRow(
    BuildContext context,
    Song song,
    AppState app,
    PlayerController player,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: context.neutral(0.52)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await app.toggleFavorite(song);
          },
          icon: Icon(
            app.isFavorite(song)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: app.isFavorite(song)
                ? AppColors.accentAlt
                : context.neutral(0.7),
          ),
        ),
      ],
    );
  }

  Widget _progress(BuildContext context, PlayerController player, Song song) {
    return StreamBuilder<Duration>(
      stream: player.player.positionStream,
      builder: (context, snapshot) {
        final duration = player.effectiveDuration;
        final total = duration.inMilliseconds.toDouble();
        final played =
            (_dragValue ?? snapshot.data?.inMilliseconds.toDouble() ?? 0).clamp(
              0.0,
              total <= 0 ? 0.0 : total,
            );
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 2.5),
              child: Slider(
                value: total <= 0 ? 0 : played,
                max: total <= 0 ? 1 : total,
                onChanged: total <= 0
                    ? null
                    : (value) {
                        setState(() => _dragValue = value);
                      },
                onChangeEnd: total <= 0
                    ? null
                    : (value) {
                        player.seek(Duration(milliseconds: value.round()));
                        setState(() => _dragValue = null);
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(Duration(milliseconds: played.round())),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.neutral(0.42),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Row(
                    children: [
                      if (player.preview) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC857)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '试听片段',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFC857),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _fmt(duration),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.neutral(0.42),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, PlayerController player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: player.toggleShuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            size: 22,
            color: player.shuffle ? AppColors.accent : context.neutral(0.55),
          ),
        ),
        IconButton(
          onPressed: () => player.previous(),
          icon: const Icon(Icons.skip_previous_rounded, size: 38),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.34
                      : 0.26,
                ),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: context.invertedFill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => player.toggle(),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: player.loading
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: context.invertedInk,
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            player.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(player.playing),
                            size: 40,
                            color: context.invertedInk,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => player.next(),
          icon: const Icon(Icons.skip_next_rounded, size: 38),
        ),
        IconButton(
          onPressed: () => _showQueue(context),
          icon: Icon(
            Icons.format_list_bulleted_rounded,
            size: 22,
            color: context.neutral(0.55),
          ),
        ),
      ],
    );
  }

  Widget _bottomActions(
    BuildContext context,
    PlayerController player,
    AppState app,
    Song song,
  ) {
    // Equal-width slots keep the row stable on narrow screens and when the
    // system font size is large.
    return Row(
      children: [
        Expanded(
          child: _action(
            context,
            icon: _showLyrics ? Icons.image_rounded : Icons.lyrics_rounded,
            label: _showLyrics ? '封面' : '歌词',
            onTap: () => setState(() => _showLyrics = !_showLyrics),
          ),
        ),
        Expanded(
          child: _action(
            context,
            icon: Icons.download_rounded,
            label: '下载',
            onTap: () async {
              try {
                final result = await app.downloadSongs([song]);
                if (context.mounted) {
                  showAppSnack(context, app.describeDownloadEnqueue(result));
                }
              } catch (error) {
                if (context.mounted) showAppSnack(context, '$error');
              }
            },
          ),
        ),
        Expanded(
          child: _action(
            context,
            icon: Icons.speed_rounded,
            label: _speedLabel(player.speed),
            onTap: () => _showSpeedSheet(context, player),
          ),
        ),
        Expanded(
          child: _action(
            context,
            icon: Icons.bedtime_rounded,
            label: _sleepLabel(player.sleepRemaining),
            onTap: () => _showSleepSheet(context, player),
          ),
        ),
        Expanded(
          child: _action(
            context,
            icon: player.errorText == null
                ? Icons.more_horiz_rounded
                : Icons.error_outline_rounded,
            label: player.errorText == null ? '更多' : '播放失败',
            onTap: () {
              if (player.errorText != null) {
                showAppSnack(context, player.errorText!);
              } else {
                showSongActions(context, song);
              }
            },
          ),
        ),
      ],
    );
  }

  String _speedLabel(double speed) {
    if (speed == 1.0) return '倍速';
    if (speed == speed.roundToDouble()) return '${speed.toInt()}x';
    return '${speed}x';
  }

  String _sleepLabel(Duration? remaining) {
    if (remaining == null) return '定时';
    final minutes = (remaining.inSeconds / 60).ceil();
    return minutes <= 0 ? '定时' : '$minutes分';
  }

  void _showSpeedSheet(BuildContext context, PlayerController player) {
    const options = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '播放速度',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final value in options)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(value == 1.0 ? '正常' : '$value x'),
                trailing: player.speed == value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: AppColors.accent,
                      )
                    : null,
                onTap: () {
                  player.setSpeed(value);
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSleepSheet(BuildContext context, PlayerController player) {
    const options = <(String, Duration?)>[
      ('关闭定时', null),
      ('15 分钟', Duration(minutes: 15)),
      ('30 分钟', Duration(minutes: 30)),
      ('60 分钟', Duration(minutes: 60)),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Text(
                    '定时停止播放',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  if (player.sleepRemaining != null)
                    Text(
                      '剩余 ${_sleepLabel(player.sleepRemaining)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.neutral(0.42),
                      ),
                    ),
                ],
              ),
            ),
            for (final option in options)
              ListTile(
                dense: true,
                title: Text(option.$1),
                onTap: () {
                  player.setSleepTimer(option.$2);
                  Navigator.pop(sheetContext);
                  showAppSnack(
                    context,
                    option.$2 == null ? '已取消定时停止' : '将在 ${option.$1}后暂停播放',
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: context.neutral(0.55)),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: context.neutral(0.42)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lyricsView(BuildContext context, PlayerController player) {
    if (player.lyricsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (player.lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.neutral(0.05),
              ),
              child: Icon(
                Icons.lyrics_outlined,
                size: 28,
                color: context.neutral(0.3),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              player.rawLyric.isEmpty ? '暂无歌词' : '歌词格式无法识别',
              style: TextStyle(color: context.neutral(0.45), fontSize: 13),
            ),
          ],
        ),
      );
    }
    const lineExtent = 48.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Pad by half the viewport so the active line sits exactly in the
        // middle, and scroll by a constant extent per line.
        final pad = ((constraints.maxHeight - lineExtent) / 2).clamp(
          0.0,
          double.infinity,
        );
        return StreamBuilder<Duration>(
          stream: player.player.positionStream,
          builder: (context, snapshot) {
            final index = player.currentLyricIndex;
            if (index != _lastLyricIndex && index >= 0 && !_draggingLyrics) {
              _lastLyricIndex = index;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_lyricController.hasClients) return;
                final target = (index * lineExtent).clamp(
                  0.0,
                  _lyricController.position.maxScrollExtent,
                );
                _lyricController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                );
              });
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _draggingLyrics = true;
                } else if (notification is ScrollEndNotification) {
                  _draggingLyrics = false;
                }
                return false;
              },
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, 0.16, 0.84, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: _lyricController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: pad),
                  itemExtent: lineExtent,
                  itemCount: player.lyrics.length,
                  itemBuilder: (context, i) {
                    final active = i == index;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => player.seek(player.lyrics[i].time),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: active ? 16.5 : 13.5,
                              height: 1.3,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: active
                                  ? Theme.of(context).colorScheme.onSurface
                                  : context.neutral(0.38),
                            ),
                            child: Text(
                              player.lyrics[i].text,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    final player = context.read<PlayerController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.35,
          builder: (context, scrollController) {
            return ListenableBuilder(
              listenable: player,
              builder: (context, _) {
                final total = player.queue.fold<Duration>(
                  Duration.zero,
                  (sum, song) => sum + Duration(seconds: song.duration),
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 10, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '播放队列',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  player.queue.isEmpty
                                      ? '暂无歌曲'
                                      : '${player.queue.length} 首 · ${_fmtLong(total)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.neutral(0.42),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await player.stop();
                              if (!context.mounted) return;
                              // Close the queue sheet and the now-empty player
                              // page in one go.
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 17,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              '停止播放',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollController: scrollController,
                        itemCount: player.queue.length,
                        onReorderItem: (oldIndex, newIndex) {
                          player.moveQueueItem(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final song = player.queue[index];
                          final active = index == player.index;
                          return Padding(
                            key: ValueKey('queue-$index'),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Material(
                              color: active
                                  ? AppColors.accent.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                leading: SizedBox(
                                  width: 26,
                                  child: Center(
                                    child: active
                                        ? const Icon(
                                            Icons.graphic_eq_rounded,
                                            color: AppColors.accent,
                                            size: 20,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: context.neutral(0.32),
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ),
                                title: Text(
                                  song.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: active ? AppColors.accent : null,
                                  ),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: context.neutral(0.45),
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: '从队列移除',
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: context.neutral(0.35),
                                  ),
                                  onPressed: () =>
                                      player.removeFromQueue(index),
                                ),
                                onTap: () => player.playSong(
                                  song,
                                  queue: player.queue,
                                  startIndex: index,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _fmt(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _fmtLong(Duration duration) {
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes % 60;
      return '${duration.inHours} 小时${minutes == 0 ? '' : ' $minutes 分'}';
    }
    return '${duration.inMinutes} 分钟';
  }
}
