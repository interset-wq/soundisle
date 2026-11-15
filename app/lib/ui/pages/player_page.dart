import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../../core/storage_bridge.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A11),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cover.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Opacity(
                opacity: 0.55,
                child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x660A0A11), Color(0xCC0A0A11), Color(0xFF0A0A11)],
                stops: [0, 0.55, 1],
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
                          constraints: BoxConstraints(minHeight: available > 0 ? available : 0),
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
                                  padding: const EdgeInsets.symmetric(vertical: 4),
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
              child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, Song song, AppState app, PlayerController player) {
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
                Text('正在播放', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.42))),
                const SizedBox(height: 3),
                SourceBadge(name: app.sourceName(song.source)),
                if (player.playInfo?.fallback == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    '已自动切换到 ${app.sourceName(player.playInfo!.fallbackSource)}',
                    style: TextStyle(fontSize: 9, color: const Color(0xFF54D68C).withValues(alpha: 0.9)),
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

  Widget _titleRow(BuildContext context, Song song, AppState app, PlayerController player) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.52))),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await app.toggleFavorite(song);
          },
          icon: Icon(
            app.isFavorite(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: app.isFavorite(song) ? AppColors.accentAlt : Colors.white.withValues(alpha: 0.7),
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
        final played = (_dragValue ?? snapshot.data?.inMilliseconds.toDouble() ?? 0).clamp(0.0, total <= 0 ? 0.0 : total);
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
                  Text(_fmt(Duration(milliseconds: played.round())),
                      style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.42))),
                  Row(
                    children: [
                      if (player.preview) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC857).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('试听片段', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFFFC857))),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(_fmt(duration), style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.42))),
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
          icon: Icon(Icons.shuffle_rounded,
              size: 22, color: player.shuffle ? AppColors.accent : Colors.white.withValues(alpha: 0.55)),
        ),
        IconButton(
          onPressed: () => player.previous(),
          icon: const Icon(Icons.skip_previous_rounded, size: 38),
        ),
        GestureDetector(
          onTap: () => player.toggle(),
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x557B6CFF), blurRadius: 24, offset: Offset(0, 6))],
            ),
            child: player.loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black87),
                  )
                : Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: Colors.black),
          ),
        ),
        IconButton(
          onPressed: () => player.next(),
          icon: const Icon(Icons.skip_next_rounded, size: 38),
        ),
        IconButton(
          onPressed: () => _showQueue(context),
          icon: Icon(Icons.format_list_bulleted_rounded, size: 22, color: Colors.white.withValues(alpha: 0.55)),
        ),
      ],
    );
  }

  Widget _bottomActions(BuildContext context, PlayerController player, AppState app, Song song) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _action(
          context,
          icon: _showLyrics ? Icons.image_rounded : Icons.lyrics_rounded,
          label: _showLyrics ? '封面' : '歌词',
          onTap: () => setState(() => _showLyrics = !_showLyrics),
        ),
        _action(
          context,
          icon: Icons.download_rounded,
          label: '下载',
          onTap: () async {
            try {
              await app.downloadSongs([song]);
              if (context.mounted) showAppSnack(context, StorageBridge.queuedMessage);
            } catch (error) {
              if (context.mounted) showAppSnack(context, '$error');
            }
          },
        ),
        _action(
          context,
          icon: player.errorText == null ? Icons.more_horiz_rounded : Icons.error_outline_rounded,
          label: player.errorText == null ? '更多' : '播放失败',
          onTap: () {
            if (player.errorText != null) {
              showAppSnack(context, player.errorText!);
            } else {
              showSongActions(context, song);
            }
          },
        ),
      ],
    );
  }

  Widget _action(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.42))),
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
            Icon(Icons.lyrics_outlined, size: 40, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(player.rawLyric.isEmpty ? '暂无歌词' : '歌词格式无法识别',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          ],
        ),
      );
    }
    return StreamBuilder<Duration>(
      stream: player.player.positionStream,
      builder: (context, snapshot) {
        final index = player.currentLyricIndex;
        if (index != _lastLyricIndex && index >= 0) {
          _lastLyricIndex = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_lyricController.hasClients) return;
            final target = (index * 46.0 - 120).clamp(0.0, _lyricController.position.maxScrollExtent);
            _lyricController.animateTo(target, duration: const Duration(milliseconds: 360), curve: Curves.easeOut);
          });
        }
        return ListView.builder(
          controller: _lyricController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 120),
          itemCount: player.lyrics.length,
          itemBuilder: (context, i) {
            final active = i == index;
            return GestureDetector(
              onTap: () => player.seek(player.lyrics[i].time),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: active ? 17 : 14,
                  height: 1.6,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                  child: Text(player.lyrics[i].text, textAlign: TextAlign.center),
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
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Row(
                        children: [
                          const Text('播放队列', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          Text('${player.queue.length} 首', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: player.queue.length,
                        itemBuilder: (context, index) {
                          final song = player.queue[index];
                          final active = index == player.index;
                          return ListTile(
                            selected: active,
                            leading: active
                                ? const Icon(Icons.graphic_eq_rounded, color: AppColors.accent)
                                : Text('${index + 1}', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                            title: Text(song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.35)),
                              onPressed: () => player.removeFromQueue(index),
                            ),
                            onTap: () => player.playSong(song, queue: player.queue, startIndex: index),
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
}
