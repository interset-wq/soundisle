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

class _LocalTab extends StatefulWidget {
  const _LocalTab({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  State<_LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<_LocalTab> {
  bool _selecting = false;
  final Set<String> _selected = {};

  List<Song> _selectedSongs(List<Song> songs) =>
      songs.where((song) => _selected.contains(song.key)).toList();

  void _enterSelection([Song? song]) {
    setState(() {
      _selecting = true;
      if (song != null) _selected.add(song.key);
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(Song song) {
    setState(() {
      if (!_selected.remove(song.key)) _selected.add(song.key);
    });
  }

  Future<void> _importFromMusic(AppState app) async {
    try {
      final summary = await app.importExportedMusic();
      if (!mounted) return;
      if (summary == null) {
        showAppSnack(context, '当前平台不支持从系统音乐目录导入');
      } else {
        showAppSnack(context, summary.message);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, '$error');
    }
  }

  Future<void> _deleteSelected(
    AppState app,
    PlayerController player,
    List<Song> picked,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${picked.length} 首本地文件'),
        content: const Text('确定从设备中删除选中的歌曲吗？此操作无法撤销。\n\n只会删除 App 内的副本，系统 Music/声屿 中的文件会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (picked.any((song) => song.key == player.current?.key)) {
        await player.pause();
      }
      final deleted = await app.deleteLocalSongs(picked);
      if (!mounted) return;
      _exitSelection();
      showAppSnack(
        context,
        deleted == picked.length
            ? '已删除 $deleted 首本地歌曲'
            : '已删除 $deleted 首，${picked.length - deleted} 首失败',
      );
    } catch (error) {
      if (mounted) showAppSnack(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final songs = app.localSongs;
    final picked = _selectedSongs(songs);
    final allSelected = songs.isNotEmpty && picked.length == songs.length;
    return RefreshIndicator(
      onRefresh: app.refreshLibrary,
      child: Column(
        children: [
          if (_selecting)
            _selectionToolbar(songs, picked, allSelected)
          else
            _listToolbar(app, songs),
          Expanded(
            child: songs.isEmpty
                ? EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: '还没有本地音乐',
                    subtitle: StorageBridge.supported
                        ? '从歌曲菜单下载，或把之前保存在 Music/声屿 的歌曲导回来'
                        : '从歌曲菜单下载后，文件会保存到下载目录并自动出现在这里',
                    action: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton(onPressed: widget.onOpenSearch, child: const Text('去搜索音乐')),
                        if (StorageBridge.supported)
                          OutlinedButton(
                            onPressed: app.importingExported ? null : () => _importFromMusic(app),
                            child: Text(app.importingExported ? '导入中…' : '从 Music/声屿 导入'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 130),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final selected = _selecting
                          ? _selected.contains(song.key)
                          : player.current?.key == song.key;
                      return SongTile(
                        song: song,
                        queue: songs,
                        index: index,
                        dense: true,
                        showSource: false,
                        selected: selected,
                        onTap: _selecting ? () => _toggle(song) : null,
                        onLongPress: _selecting ? null : () => _enterSelection(song),
                        trailing: _selecting
                            ? Icon(
                                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                size: 20,
                                color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.28),
                              )
                            : Row(
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
          if (_selecting) _batchBar(app, player, picked),
        ],
      ),
    );
  }

  Widget _listToolbar(AppState app, List<Song> songs) {
    return _ListToolbar(
      icon: Icons.folder_rounded,
      title: '已下载到本地',
      subtitle: StorageBridge.supported
          ? '${songs.length} 首歌曲 · 副本在系统 Music/声屿'
          : (app.settings.downloadDir.isEmpty ? '${songs.length} 首歌曲' : app.settings.downloadDir),
      actions: [
        if (StorageBridge.supported)
          IconButton(
            tooltip: '从 Music/声屿 导入',
            visualDensity: VisualDensity.compact,
            onPressed: app.importingExported ? null : () => _importFromMusic(app),
            icon: app.importingExported
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.library_music_rounded, size: 20),
          ),
        IconButton(
          tooltip: '重新扫描',
          visualDensity: VisualDensity.compact,
          onPressed: app.scanning
              ? null
              : () async {
                  try {
                    await app.rescanLibrary();
                    if (mounted) showAppSnack(context, '扫描完成，共 ${app.localSongs.length} 首');
                  } catch (error) {
                    if (mounted) showAppSnack(context, '$error');
                  }
                },
          icon: app.scanning
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
        if (songs.isNotEmpty)
          IconButton(
            tooltip: '批量管理',
            visualDensity: VisualDensity.compact,
            onPressed: () => _enterSelection(),
            icon: const Icon(Icons.checklist_rounded, size: 20),
          ),
        if (songs.isNotEmpty)
          IconButton(
            tooltip: '播放全部',
            onPressed: () => playSongList(context, songs, 0),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 28, color: AppColors.accent),
          ),
      ],
    );
  }

  Widget _selectionToolbar(List<Song> songs, List<Song> picked, bool allSelected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '退出多选',
            onPressed: _exitSelection,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              picked.isEmpty ? '请选择歌曲' : '已选 ${picked.length} 首',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: songs.isEmpty
                ? null
                : () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(songs.map((song) => song.key));
                      }
                    }),
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
        ],
      ),
    );
  }

  Widget _batchBar(AppState app, PlayerController player, List<Song> picked) {
    final enabled = picked.isNotEmpty;
    return Material(
      color: AppColors.darkSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _BatchAction(
                  icon: Icons.play_arrow_rounded,
                  label: '播放',
                  onTap: enabled
                      ? () {
                          final songs = List<Song>.of(picked);
                          _exitSelection();
                          playSongList(context, songs, 0);
                        }
                      : null,
                ),
              ),
              Expanded(
                child: _BatchAction(
                  icon: Icons.queue_play_next_rounded,
                  label: '加入队列',
                  onTap: enabled
                      ? () {
                          for (final song in picked) {
                            player.addToQueue(song);
                          }
                          _exitSelection();
                          showAppSnack(context, '已加入 ${picked.length} 首到播放队列');
                        }
                      : null,
                ),
              ),
              Expanded(
                child: _BatchAction(
                  icon: Icons.playlist_add_rounded,
                  label: '加入歌单',
                  onTap: enabled ? () => showAddToCollectionSongs(context, picked) : null,
                ),
              ),
              Expanded(
                child: _BatchAction(
                  icon: Icons.delete_outline_rounded,
                  label: '删除',
                  color: Colors.redAccent,
                  onTap: enabled ? () => _deleteSelected(app, player, picked) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = enabled ? (color ?? Colors.white) : Colors.white.withValues(alpha: 0.24);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: tint),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: enabled ? (color ?? Colors.white.withValues(alpha: 0.75)) : tint,
              ),
            ),
          ],
        ),
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
