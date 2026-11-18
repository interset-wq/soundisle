import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../pages/playlist_page.dart';
import '../theme.dart';
import 'common.dart';
import 'cover_art.dart';
import 'player_route.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.queue,
    this.index,
    this.onTap,
    this.showCover = true,
    this.showSource = true,
    this.dense = false,
    this.trailing,
    this.selected = false,
    this.onLongPress,
  });

  final Song song;
  final List<Song>? queue;
  final int? index;
  final VoidCallback? onTap;
  final bool showCover;
  final bool showSource;
  final bool dense;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final api = app.api;
    final cover = api.coverUrl(song.cover, source: song.source);
    return Material(
      color: selected ? context.neutral(0.055) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? () => playSongList(context, queue ?? [song], index ?? 0),
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 7 : 9),
          child: Row(
            children: [
              if (showCover) ...[
                CoverArt(url: cover, size: dense ? 44 : 52, radius: 11, seed: song.name),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: dense ? 13.5 : 14.5,
                              fontWeight: FontWeight.w600,
                              color: selected ? AppColors.accent : null,
                            ),
                          ),
                        ),
                        if (song.isVip) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC857).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('VIP', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFFFC857))),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (showSource) ...[
                          SourceBadge(name: app.sourceName(song.source), dense: true),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            song.album.isEmpty ? song.artist : '${song.artist} · ${song.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: context.neutral(0.44)),
                          ),
                        ),
                        if (!dense && song.duration > 0) ...[
                          const SizedBox(width: 8),
                          Text(song.durationText, style: TextStyle(fontSize: 11, color: context.neutral(0.32))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              trailing ??
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.more_horiz_rounded, size: 20, color: context.neutral(0.45)),
                    onPressed: () => showSongActions(context, song),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> playSongList(BuildContext context, List<Song> songs, int index,
    {bool openPlayer = true}) async {
  if (songs.isEmpty) return;
  final player = context.read<PlayerController>();
  final app = context.read<AppState>();
  final safeIndex = index.clamp(0, songs.length - 1);
  // Start playback first so the player page has metadata to show immediately.
  await player.playSong(songs[safeIndex], queue: songs, startIndex: safeIndex);
  if (context.mounted && player.errorText != null) {
    showAppSnack(context, player.errorText!);
  }
  if (context.mounted && player.playInfo?.fallback == true) {
    showAppSnack(context, '原音源不可用，已自动切换到 ${app.sourceName(player.playInfo!.fallbackSource)}');
  }
  if (context.mounted && player.playInfo?.preview == true) {
    showAppSnack(context, '当前为试听片段，登录或配置 Cookie 后可能获得完整歌曲');
  }
  app.refreshDownloads();
  if (openPlayer && app.tapSongOpensPlayer && context.mounted) {
    await openPlayerPage(context);
  }
}

Future<void> showSongActions(BuildContext context, Song song) async {
  final app = context.read<AppState>();
  final player = context.read<PlayerController>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final favorite = app.isFavorite(song);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    children: [
                      CoverArt(url: app.api.coverUrl(song.cover, source: song.source), size: 54, seed: song.name),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text('${song.artist}${song.album.isEmpty ? '' : ' · ${song.album}'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.neutral(0.45))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('立即播放'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    playSongList(context, [song], 0);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.queue_play_next_rounded),
                  title: const Text('下一首播放'),
                  onTap: () {
                    player.playNext(song);
                    Navigator.pop(sheetContext);
                    showAppSnack(context, '已添加到下一首');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('添加到播放队列'),
                  onTap: () {
                    player.addToQueue(song);
                    Navigator.pop(sheetContext);
                    showAppSnack(context, '已添加到播放队列');
                  },
                ),
                ListTile(
                  leading: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: favorite ? AppColors.accentAlt : null),
                  title: Text(favorite ? '取消喜欢' : '喜欢'),
                  onTap: () async {
                    await app.toggleFavorite(song);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_check_rounded),
                  title: const Text('添加到歌单'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showAddToCollection(context, song);
                  },
                ),
                if (song.link.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('复制歌曲链接'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: song.link));
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (context.mounted) showAppSnack(context, '链接已复制');
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('下载到本地'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
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
                if (song.source == 'local')
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('删除本地文件', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除本地文件'),
                          content: Text('确定从设备中删除「${song.name}」吗？此操作无法撤销。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        if (player.current?.key == song.key) await player.pause();
                        await app.api.deleteLocalSong(song);
                        await app.refreshLibrary();
                        if (context.mounted) showAppSnack(context, '已删除本地文件');
                      } catch (error) {
                        if (context.mounted) showAppSnack(context, '$error');
                      }
                    },
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
          ),
        ),
      );
    },
  );
}

Future<void> showAddToCollection(BuildContext context, Song song) =>
    showAddToCollectionSongs(context, [song]);

Future<void> showAddToCollectionSongs(BuildContext context, List<Song> songs) async {
  if (songs.isEmpty) return;
  final app = context.read<AppState>();
  final single = songs.length == 1;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final collections = app.collections.where((e) => true).toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      single ? '添加到歌单' : '添加 ${songs.length} 首到歌单',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                for (final collection in collections)
                  ListTile(
                    leading: Icon(collection.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded,
                        color: collection.isFavorites ? AppColors.accentAlt : null),
                    title: Text(collection.name),
                    subtitle: Text('${collection.songs.length} 首'),
                    trailing: songs.every(collection.songs.contains)
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    onTap: () async {
                      await app.addToCollection(collection.id, songs);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (context.mounted) {
                        showAppSnack(
                          context,
                          single ? '已添加到「${collection.name}」' : '已添加 ${songs.length} 首到「${collection.name}」',
                        );
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('新建歌单'),
                  onTap: () async {
                    final name = await _askName(context, '新建歌单');
                    if (name == null || name.trim().isEmpty) return;
                    final collection = await app.createCollection(name.trim());
                    await app.addToCollection(collection.id, songs);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
          ),
        ),
      );
    },
  );
}

Future<String?> _askName(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '歌单名称'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('创建')),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.onTap, this.width = 150});

  final Playlist playlist;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cover = app.api.coverUrl(playlist.cover, source: playlist.source);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverArt(url: cover, size: width, radius: 16, seed: playlist.name, icon: Icons.queue_music_rounded),
                Positioned(
                  right: 8,
                  top: 8,
                  child: ifTrue(playlist.playCount > 0, _countChip(playlist.playCount)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 2),
            Text(playlist.creator.isEmpty ? app.sourceName(playlist.source) : playlist.creator,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: context.neutral(0.4))),
          ],
        ),
      ),
    );
  }

  Widget _countChip(int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.42), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 11, color: Colors.white),
            const SizedBox(width: 1),
            Text(formatCount(count), style: const TextStyle(fontSize: 9, color: Colors.white)),
          ],
        ),
      );

  Widget ifTrue(bool condition, Widget child) => condition ? child : const SizedBox.shrink();
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.collection, this.onTap, this.width = 150});

  final Collection collection;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final first = collection.songs.isNotEmpty ? collection.songs.first : null;
    final cover = first == null ? '' : app.api.coverUrl(first.cover, source: first.source);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverArt(url: cover, size: width, radius: 16, seed: collection.name, icon: collection.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded),
                if (collection.isFavorites)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.36), shape: BoxShape.circle),
                      child: const Icon(Icons.favorite_rounded, size: 13, color: AppColors.accentAlt),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(collection.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${collection.songs.length} 首歌曲', style: TextStyle(fontSize: 10.5, color: context.neutral(0.4))),
          ],
        ),
      ),
    );
  }
}

class TopListCard extends StatelessWidget {
  const TopListCard({super.key, required this.topList, this.onTap, this.width = 200});

  final TopList topList;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cover = app.api.coverUrl(topList.cover, source: topList.source);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [context.neutral(0.07), context.neutral(0.025)],
            ),
            border: Border.all(color: context.subtleBorder),
          ),
          child: Row(
            children: [
              CoverArt(url: cover, size: 62, radius: 12, seed: topList.name, icon: Icons.leaderboard_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topList.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(topList.updateFrequency.isEmpty ? '${topList.trackCount} 首' : topList.updateFrequency,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: context.neutral(0.4))),
                    const SizedBox(height: 4),
                    SourceBadge(name: app.sourceName(topList.source), dense: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void openPlaylist(BuildContext context, Playlist playlist, {List<Song>? initialSongs, String type = 'playlist'}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlaylistPage(
      source: playlist.source,
      id: playlist.id,
      name: playlist.name,
      cover: playlist.cover,
      creator: playlist.creator,
      description: playlist.description,
      trackCount: playlist.trackCount,
      initialSongs: initialSongs,
      type: type,
    ),
  ));
}
