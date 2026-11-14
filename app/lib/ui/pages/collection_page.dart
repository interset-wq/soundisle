import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.id});

  final String id;

  Collection? _find(AppState app) {
    for (final collection in app.collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final collection = _find(app);
    if (collection == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('歌单')),
        body: const EmptyState(icon: Icons.queue_music_rounded, title: '歌单不存在'),
      );
    }
    final songs = collection.songs;
    final first = songs.isNotEmpty ? songs.first : null;
    final cover = first == null ? '' : app.api.coverUrl(first.cover, source: first.source);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: app.refreshCollections,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              backgroundColor: const Color(0xFF0A0A11),
              actions: [
                IconButton(
                  onPressed: () => _showActions(context, app, collection),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover.isNotEmpty)
                      Opacity(opacity: 0.24, child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withValues(alpha: 0.32),
                            const Color(0xFF0A0A11),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CoverArt(
                            url: cover,
                            size: 120,
                            radius: 22,
                            seed: collection.name,
                            icon: collection.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collection.isFavorites ? '我喜欢的音乐' : '我的歌单',
                                  style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.5)),
                                ),
                                const SizedBox(height: 5),
                                Text(collection.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.15)),
                                const SizedBox(height: 8),
                                Text('${songs.length} 首歌曲',
                                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.48))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: songs.isEmpty ? null : () => playSongList(context, songs, 0),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('播放全部 (${songs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: songs.isEmpty ? null : () => _shuffle(context, songs),
                      icon: const Icon(Icons.shuffle_rounded),
                      tooltip: '随机播放',
                    ),
                  ],
                ),
              ),
            ),
            if (songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: collection.isFavorites ? Icons.favorite_border_rounded : Icons.playlist_add_rounded,
                  title: collection.isFavorites ? '还没有喜欢的歌曲' : '歌单还是空的',
                  subtitle: '在歌曲菜单中选择「喜欢」或「添加到歌单」',
                ),
              )
            else
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return SongTile(
                    song: song,
                    queue: songs,
                    index: index,
                    dense: true,
                    selected: player.current?.key == song.key,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${index + 1}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25))),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.white.withValues(alpha: 0.35)),
                          tooltip: '从歌单移除',
                          onPressed: () => app.removeFromCollection(collection.id, song),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Future<void> _shuffle(BuildContext context, List<Song> songs) async {
    final list = List<Song>.from(songs)..shuffle();
    await playSongList(context, list, 0);
  }

  Future<void> _showActions(BuildContext context, AppState app, Collection collection) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!collection.isFavorites)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('重命名歌单'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final name = await _askName(context, collection.name);
                  if (name == null || name.trim().isEmpty) return;
                  await app.renameCollection(collection.id, name.trim());
                },
              ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载全部'),
              onTap: () async {
                Navigator.pop(sheet);
                await app.downloadSongs(collection.songs);
                if (context.mounted) showAppSnack(context, '已加入下载队列');
              },
            ),
            if (!collection.isFavorites)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('删除歌单', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('删除歌单'),
                      content: Text('确定删除「${collection.name}」吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await app.deleteCollection(collection.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(BuildContext context, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
