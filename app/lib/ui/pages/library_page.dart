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
import 'collection_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final favoriteCount = app.favorites?.songs.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐库', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: widget.onOpenSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 6),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.42),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: '本地 ${app.localSongs.length}'),
            Tab(text: '喜欢 $favoriteCount'),
            Tab(text: '歌单 ${app.collections.length}'),
            const Tab(text: '下载'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LocalTab(onOpenSearch: widget.onOpenSearch),
          const _FavoritesTab(),
          _CollectionsTab(onOpenSearch: widget.onOpenSearch),
          const _DownloadsTab(),
        ],
      ),
    );
  }
}

class _LocalTab extends StatelessWidget {
  const _LocalTab({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final songs = app.localSongs;
    return RefreshIndicator(
      onRefresh: app.refreshLibrary,
      child: Column(
        children: [
          _ListToolbar(
            icon: Icons.folder_rounded,
            title: '已下载到本地',
            subtitle: StorageBridge.supported
                ? '${songs.length} 首歌曲 · 副本在系统 Music/声屿'
                : (app.settings.downloadDir.isEmpty ? '${songs.length} 首歌曲' : app.settings.downloadDir),
            actions: [
              TextButton.icon(
                onPressed: app.scanning
                    ? null
                    : () async {
                        try {
                          await app.rescanLibrary();
                          if (context.mounted) showAppSnack(context, '扫描完成，共 ${app.localSongs.length} 首');
                        } catch (error) {
                          if (context.mounted) showAppSnack(context, '$error');
                        }
                      },
                icon: app.scanning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(app.scanning ? '扫描中' : '重新扫描', style: const TextStyle(fontSize: 11.5)),
              ),
              if (songs.isNotEmpty)
                IconButton(
                  tooltip: '播放全部',
                  onPressed: () => playSongList(context, songs, 0),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 28, color: AppColors.accent),
                ),
            ],
          ),
          Expanded(
            child: songs.isEmpty
                ? EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: '还没有本地音乐',
                    subtitle: '从歌曲菜单下载后，文件会保存到下载目录并自动出现在这里',
                    action: FilledButton(onPressed: onOpenSearch, child: const Text('去搜索音乐')),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 130),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongTile(
                        song: song,
                        queue: songs,
                        index: index,
                        dense: true,
                        showSource: false,
                        selected: player.current?.key == song.key,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${index + 1}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25))),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.more_horiz_rounded, size: 19, color: Colors.white.withValues(alpha: 0.4)),
                              onPressed: () => showSongActions(context, song),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final songs = app.favorites?.songs ?? const <Song>[];
    return Column(
      children: [
        _ListToolbar(
          icon: Icons.favorite_rounded,
          iconColor: AppColors.accentAlt,
          title: '我喜欢的音乐',
          subtitle: '${songs.length} 首歌曲',
          actions: [
            if (songs.isNotEmpty)
              IconButton(
                tooltip: '播放全部',
                onPressed: () => playSongList(context, songs, 0),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 28, color: AppColors.accent),
              ),
          ],
        ),
        Expanded(
          child: songs.isEmpty
              ? const EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: '还没有喜欢的歌曲',
                  subtitle: '播放时点击心形按钮，喜欢的音乐会出现在这里',
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 130),
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
                            icon: Icon(Icons.more_horiz_rounded, size: 19, color: Colors.white.withValues(alpha: 0.4)),
                            onPressed: () => showSongActions(context, song),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 6
            : width >= 760
                ? 5
                : width >= 560
                    ? 4
                    : width >= 400
                        ? 3
                        : 2;
        const spacing = 14.0;
        final tileWidth = (width - 32 - spacing * (columns - 1)) / columns;
        final collections = app.collections;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('我的歌单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final name = await askCollectionName(context);
                        if (name == null || name.trim().isEmpty) return;
                        await app.createCollection(name.trim());
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: 18,
                  childAspectRatio: tileWidth / (tileWidth + 52),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == collections.length) {
                      return _NewCollectionCard(onTap: () async {
                        final name = await askCollectionName(context);
                        if (name == null || name.trim().isEmpty) return;
                        await app.createCollection(name.trim());
                      });
                    }
                    final collection = collections[index];
                    return CollectionCard(
                      collection: collection,
                      width: tileWidth,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CollectionPage(id: collection.id),
                      )),
                    );
                  },
                  childCount: collections.length + 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NewCollectionCard extends StatelessWidget {
  const _NewCollectionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(Icons.add_rounded, size: 30, color: Colors.white.withValues(alpha: 0.32)),
            ),
          ),
          const SizedBox(height: 8),
          Text('新建歌单', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tasks = app.downloads;
    final active = tasks.where((e) => e.status == 'downloading' || e.status == 'waiting').length;
    return RefreshIndicator(
      onRefresh: app.refreshDownloads,
      child: Column(
        children: [
          _ListToolbar(
            icon: Icons.download_rounded,
            title: active > 0 ? '正在下载 $active 个任务' : '下载任务',
            subtitle: StorageBridge.supported ? '完成后自动保存到系统 Music/声屿' : app.settings.downloadDir,
            actions: [
              if (tasks.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    for (final task in tasks.where((e) => e.status == 'done' || e.status == 'failed' || e.status == 'canceled')) {
                      await app.removeDownload(task.id);
                    }
                  },
                  child: const Text('清除记录', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          Expanded(
            child: tasks.isEmpty
                ? const EmptyState(
                    icon: Icons.download_for_offline_outlined,
                    title: '暂无下载任务',
                    subtitle: '歌曲、专辑和歌单都可以一键下载到本地',
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 130),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) => _DownloadTile(task: tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cover = app.api.coverUrl(task.cover, source: task.source);
    final status = _statusText(task);
    final local = _localSong(app);
    final exported = app.exportedLocations[task.id];
    final exportError = app.exportErrors[task.id];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: local == null ? null : () => playSongList(context, app.localSongs, app.localSongs.indexWhere((e) => e.key == local.key)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CoverArt(url: cover, size: 50, radius: 11, seed: task.name),
                  if (task.status == 'downloading')
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        value: task.progress == 0 ? null : task.progress,
                        strokeWidth: 2.6,
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        SourceBadge(name: app.sourceName(task.source), dense: true),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task.artist.isEmpty ? status : '${task.artist} · $status',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: task.status == 'failed' ? Colors.redAccent.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (task.status == 'downloading') ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: task.progress == 0 ? null : task.progress,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                    if (task.status == 'done' && exported != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.folder_rounded, size: 11, color: Color(0xFF54D68C)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '已保存到 $exported',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF54D68C)),
                            ),
                          ),
                        ],
                      ),
                    ] else if (task.status == 'done' && exportError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '保存到系统音乐库失败：$exportError',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.orangeAccent.withValues(alpha: 0.85)),
                      ),
                    ],
                  ],
                ),
              ),
              if (task.status == 'failed')
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '重试',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () async {
                    try {
                      await app.retryDownload(task.id);
                    } catch (error) {
                      if (context.mounted) showAppSnack(context, '重试失败：$error');
                    }
                  },
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '移除任务',
                icon: Icon(
                  task.status == 'done' ? Icons.check_circle_rounded : Icons.close_rounded,
                  size: task.status == 'done' ? 20 : 18,
                  color: task.status == 'done' ? const Color(0xFF54D68C) : Colors.white.withValues(alpha: 0.35),
                ),
                onPressed: () => app.removeDownload(task.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Song? _localSong(AppState app) {
    if (task.path.isEmpty) return null;
    for (final song in app.localSongs) {
      if (song.extra['path'] == task.path) return song;
    }
    return null;
  }

  String _statusText(DownloadTask task) {
    switch (task.status) {
      case 'waiting':
        return '等待下载';
      case 'downloading':
        return '${(task.progress * 100).toStringAsFixed(0)}%';
      case 'done':
        return '已完成';
      case 'failed':
        return task.error.isEmpty ? '下载失败' : '下载失败：${task.error}';
      case 'canceled':
        return '已取消';
      default:
        return task.status;
    }
  }
}

class _ListToolbar extends StatelessWidget {
  const _ListToolbar({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.accent).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor ?? AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.38))),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

Future<String?> askCollectionName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('新建歌单'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '给歌单起个名字'),
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
