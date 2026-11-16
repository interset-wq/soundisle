import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/player_controller.dart';
import 'cover_art.dart';
import 'player_route.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    if (!player.hasSong) return const SizedBox.shrink();
    final app = context.watch<AppState>();
    final song = player.current!;
    final cover = app.api.coverUrl(song.cover, source: song.source);
    return Material(
      color: const Color(0xFF16161F),
      child: InkWell(
        onTap: () => openPlayerPage(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: player.player.positionStream,
              builder: (context, snapshot) {
                final total = player.effectiveDuration.inMilliseconds;
                final pos = snapshot.data?.inMilliseconds ?? 0;
                final value = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0);
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFB3A9FF)),
                );
              },
            ),
            SizedBox(
              height: 66,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  CoverArt(
                    url: cover,
                    size: 46,
                    radius: 10,
                    seed: song.name,
                    heroTag: 'player-cover',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(song.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            ),
                            if (player.preview) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFC857).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('试听',
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFFFFC857))),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await app.toggleFavorite(song);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(app.isFavorite(song) ? '已添加到我喜欢的音乐' : '已取消喜欢'),
                          duration: const Duration(seconds: 1),
                        ));
                      }
                    },
                    icon: Icon(
                      app.isFavorite(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 20,
                      color: app.isFavorite(song) ? const Color(0xFFFF6B9A) : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  IconButton(
                    onPressed: () => player.toggle(),
                    icon: player.loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                  ),
                  IconButton(
                    onPressed: () => player.next(),
                    icon: const Icon(Icons.skip_next_rounded, size: 26),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
