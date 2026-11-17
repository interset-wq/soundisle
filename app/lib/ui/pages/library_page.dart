import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/local_grouping.dart';
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
  LocalGroupMode _groupMode = LocalGroupMode.none;
  final Set<String> _expandedGroups = {};

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Song> _selectedSongs(List<Song> songs) =>
      songs.where((song) => _selected.contains(song.key)).toList();

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  void _clearSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  void _setGroupMode(LocalGroupMode mode) {
    setState(() {
      _groupMode = mode;
      _expandedGroups.clear();
    });
  }

  void _toggleGroup(SongGroup group) {
    setState(() {
      final keys = group.songs.map((song) => song.key).toList();
      if (keys.every(_selected.contains)) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  void _toggleExpanded(SongGroup group) {
    setState(() {
      if (!_expandedGroups.remove(group.key)) _expandedGroups.add(group.key);
    });
  }

  void _enterSelection([Song? song]) {
    setState(() {
      _selecting = true;
      // Selection works on the complete library; leaving the search filter
      // active would make "全选" mean something different from what is shown.
      _searching = false;
      _query = '';
      _searchController.clear();
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
    final allSongs = app.localSongs;
    final songs = filterLocalSongs(allSongs, _query);
    final picked = _selectedSongs(songs);
    final allSelected = songs.isNotEmpty && picked.length == songs.length;
    return RefreshIndicator(
      onRefresh: app.refreshLibrary,
      child: Column(
        children: [
          if (_selecting)
            _selectionToolbar(songs, picked, allSelected)
          else
            _listToolbar(app, allSongs, songs),
          if (_searching) _searchField(),
          if (allSongs.isNotEmpty && !_selecting) _modeChips(),
          Expanded(
            child: allSongs.isEmpty
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
                : songs.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: '没有匹配的歌曲',
                        subtitle: '换个关键词，或清除搜索查看全部 ${allSongs.length} 首',
                        action: OutlinedButton(onPressed: _clearSearch, child: const Text('清除搜索')),
                      )
                    : _groupMode == LocalGroupMode.none
                        ? _songList(songs, player)
                        : _groupedList(songs, player),
          ),
          if (_selecting) _batchBar(app, player, picked),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索歌名、歌手、专辑',
          hintStyle: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.32)),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.white.withValues(alpha: 0.38)),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 17, color: Colors.white.withValues(alpha: 0.45)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _modeChips() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        children: [
          _ModeChip(
            icon: Icons.list_rounded,
            label: '歌曲',
            selected: _groupMode == LocalGroupMode.none,
            onTap: () => _setGroupMode(LocalGroupMode.none),
          ),
          const SizedBox(width: 8),
          _ModeChip(
            icon: Icons.person_rounded,
            label: '歌手',
            selected: _groupMode == LocalGroupMode.artist,
            onTap: () => _setGroupMode(LocalGroupMode.artist),
          ),
          const SizedBox(width: 8),
          _ModeChip(
            icon: Icons.album_rounded,
            label: '专辑',
            selected: _groupMode == LocalGroupMode.album,
            onTap: () => _setGroupMode(LocalGroupMode.album),
          ),
        ],
      ),
    );
  }

  Widget _songList(List<Song> songs, PlayerController player) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 130),
      itemCount: songs.length,
      itemBuilder: (context, index) => _songTile(
        song: songs[index],
        queue: songs,
        index: index,
        player: player,
      ),
    );
  }

  Widget _groupedList(List<Song> songs, PlayerController player) {
    final groups = groupLocalSongs(songs, _groupMode);
    final app = context.read<AppState>();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 130),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final expanded = _selecting || _expandedGroups.contains(group.key);
        final first = group.songs.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(
              title: group.title,
              subtitle: group.subtitle.isEmpty
                  ? '${group.songs.length} 首'
                  : '${group.subtitle} · ${group.songs.length} 首',
              coverUrl: app.api.coverUrl(first.cover, source: first.source),
              total: group.songs.length,
              selectedCount: group.songs.where((song) => _selected.contains(song.key)).length,
              expanded: expanded,
              selecting: _selecting,
              onTap: _selecting ? () => _toggleGroup(group) : () => _toggleExpanded(group),
              onPlay: _selecting ? null : () => playSongList(context, group.songs, 0),
            ),
            if (expanded)
              for (var i = 0; i < group.songs.length; i++)
                _songTile(
                  song: group.songs[i],
                  queue: group.songs,
                  index: i,
                  player: player,
                  indented: true,
                ),
          ],
        );
      },
    );
  }

  Widget _songTile({
    required Song song,
    required List<Song> queue,
    required int index,
    required PlayerController player,
    bool indented = false,
  }) {
    final selected = _selecting ? _selected.contains(song.key) : player.current?.key == song.key;
    final tile = SongTile(
      song: song,
      queue: queue,
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
    if (!indented) return tile;
    return Padding(padding: const EdgeInsets.only(left: 10), child: tile);
  }

  Widget _listToolbar(AppState app, List<Song> allSongs, List<Song> visible) {
    final searching = _query.trim().isNotEmpty;
    return _ListToolbar(
      icon: Icons.folder_rounded,
      title: searching ? '找到 ${visible.length} 首' : '已下载到本地',
      subtitle: searching
          ? '共 ${allSongs.length} 首本地歌曲'
          : StorageBridge.supported
              ? '${allSongs.length} 首歌曲 · 副本在系统 Music/声屿'
              : (app.settings.downloadDir.isEmpty ? '${allSongs.length} 首歌曲' : app.settings.downloadDir),
      actions: [
        if (allSongs.isNotEmpty)
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索本地音乐',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded, size: 20),
          ),
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
        if (allSongs.isNotEmpty && !_searching)
          IconButton(
            tooltip: '批量管理',
            visualDensity: VisualDensity.compact,
            onPressed: () => _enterSelection(),
            icon: const Icon(Icons.checklist_rounded, size: 20),
          ),
        if (visible.isNotEmpty)
          IconButton(
            tooltip: '播放全部',
            onPressed: () => playSongList(context, visible, 0),
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.45)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.total,
    required this.selectedCount,
    required this.expanded,
    required this.selecting,
    required this.onTap,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final int total;
  final int selectedCount;
  final bool expanded;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              CoverArt(url: coverUrl, size: 44, radius: 12, seed: title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selecting && selectedCount > 0 ? AppColors.accent : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
              if (selecting)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    selectedCount == 0
                        ? Icons.radio_button_unchecked_rounded
                        : (selectedCount == total
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline_rounded),
                    size: 22,
                    color: selectedCount == 0 ? Colors.white.withValues(alpha: 0.28) : AppColors.accent,
                  ),
                )
              else ...[
                IconButton(
                  tooltip: '播放这组',
                  visualDensity: VisualDensity.compact,
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 26, color: AppColors.accent),
                ),
                Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
              ],
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
    final missingAssets = tasks
        .where((e) => e.status == 'done' && !e.repairing && (e.lyricPath.isEmpty || e.coverPath.isEmpty))
        .length;
    return RefreshIndicator(
      onRefresh: app.refreshDownloads,
      child: Column(
        children: [
          _ListToolbar(
            icon: Icons.download_rounded,
            title: active > 0 ? '正在下载 $active 个任务' : '下载任务',
            subtitle: StorageBridge.supported ? '完成后自动保存到系统 Music/声屿' : app.settings.downloadDir,
            actions: [
              if (missingAssets > 0)
                IconButton(
                  tooltip: '补全全部歌词/封面',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 19),
                  onPressed: () async {
                    try {
                      final queued = await app.repairMissingDownloadAssets();
                      if (context.mounted) {
                        showAppSnack(
                          context,
                          queued == 0 ? '没有需要补全的任务' : '正在补全 $queued 个任务的歌词与封面',
                        );
                      }
                    } catch (error) {
                      if (context.mounted) showAppSnack(context, '补全失败：$error');
                    }
                  },
                ),
              if (tasks.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final removed = await app.clearFinishedDownloads();
                    if (context.mounted && removed > 0) {
                      showAppSnack(context, '已清除 $removed 条下载记录');
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
    final cover = task.coverPath.isNotEmpty
        ? app.api.localCoverUrl(task.coverPath)
        : app.api.coverUrl(task.cover, source: task.source);
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
              if (task.repairing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (task.status == 'done' &&
                  (task.lyricPath.isEmpty || task.coverPath.isEmpty))
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '补全歌词/封面',
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 19),
                  onPressed: () async {
                    try {
                      await app.repairDownloadAssets(task.id);
                      if (context.mounted) showAppSnack(context, '正在补全歌词与封面');
                    } catch (error) {
                      if (context.mounted) showAppSnack(context, '补全失败：$error');
                    }
                  },
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
    if (task.repairing) return '正在补全歌词与封面';
    switch (task.status) {
      case 'waiting':
        return '等待下载';
      case 'downloading':
        return '${(task.progress * 100).toStringAsFixed(0)}%';
      case 'done':
        final assets = [
          if (task.lyricPath.isNotEmpty) '歌词',
          if (task.coverPath.isNotEmpty) '封面',
        ];
        return assets.isEmpty ? '已完成' : '已完成 · ${assets.join(' / ')}';
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
