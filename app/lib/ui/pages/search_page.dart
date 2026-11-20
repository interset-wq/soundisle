import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';
import 'playlist_page.dart';

const _searchTypes = ['song', 'playlist', 'album'];
const _historyKey = 'search_history_v1';
const _suggestions = ['周杰伦', '林俊杰', '陈奕迅', '邓紫棋', '五月天', '薛之谦', '毛不易', 'Taylor Swift'];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.showBack = true});

  final bool showBack;

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final Map<String, SearchResponse> _results = {};
  final Set<String> _loadingTypes = {};
  final Map<String, String> _errors = {};
  final Set<String> _selectedSources = {};
  List<String> _history = [];
  String _lastQuery = '';
  // Incremented for every new query/source change so an older, slower request
  // cannot overwrite the results of a newer search.
  int _searchGeneration = 0;
  bool _parsingLink = false;
  bool _sourcesInitialized = false;

  String get _currentType => _searchTypes[_tabController.index];

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      final type = _currentType;
      if (_lastQuery.isNotEmpty && !_results.containsKey(type) && !_loadingTypes.contains(type)) {
        _searchType(type);
      }
    });
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSources());
  }

  void _initSources() {
    if (_sourcesInitialized) return;
    final app = context.read<AppState>();
    final searchable = app.sources.where((e) => e.search).map((e) => e.id).toSet();
    final defaults = app.defaultSources.where(searchable.contains).toList();
    setState(() {
      _selectedSources
        ..clear()
        ..addAll(defaults.isNotEmpty ? defaults : searchable.take(5));
      _sourcesInitialized = true;
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_historyKey) ?? const [];
    if (!mounted) return;
    setState(() => _history = stored);
  }

  Future<void> _saveHistory(String query) async {
    if (query.isEmpty) return;
    final next = <String>[query, ..._history.where((e) => e != query)].take(12).toList();
    setState(() => _history = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  void focusSearch() {
    _focusNode.requestFocus();
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  bool _looksLikeLink(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        value.contains('music.163.com') ||
        value.contains('y.qq.com') ||
        value.contains('kugou.com') ||
        value.contains('kuwo.cn') ||
        value.contains('bilibili.com');
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _focusNode.unfocus();
    if (_looksLikeLink(query)) {
      await _parseLink(query);
      return;
    }
    setState(() {
      _lastQuery = query;
      _searchGeneration++;
      _results.clear();
      _errors.clear();
      _loadingTypes.clear();
    });
    unawaited(_saveHistory(query));
    await _searchType(_currentType);
  }

  Future<void> _parseLink(String link) async {
    final api = context.read<ApiClient>();
    setState(() {
      _parsingLink = true;
      _lastQuery = link;
    });
    try {
      final detail = await api.parseLink(link);
      if (!mounted) return;
      final playlist = detail.playlist;
      if (playlist != null && detail.songs.isNotEmpty) {
        openPlaylist(
          context,
          playlist,
          initialSongs: detail.songs,
          type: detail.type == 'album' ? 'album' : 'playlist',
        );
        return;
      }
      if (detail.songs.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlaylistPage(
            source: detail.songs.first.source,
            name: playlist?.name ?? '链接解析结果',
            cover: playlist?.cover ?? detail.songs.first.cover,
            creator: playlist?.creator ?? '',
            initialSongs: detail.songs,
          ),
        ));
        return;
      }
      final song = detail.song;
      if (song != null) {
        await context.read<PlayerController>().playSong(song, queue: [song], startIndex: 0);
        return;
      }
      if (mounted) showAppSnack(context, '没有从链接中解析到歌曲');
    } catch (error) {
      if (mounted) showAppSnack(context, error is ApiException ? error.message : '$error');
    } finally {
      if (mounted) setState(() => _parsingLink = false);
    }
  }

  Future<void> _searchType(String type) async {
    if (_lastQuery.isEmpty) return;
    if (_loadingTypes.contains(type)) return;
    if (_results.containsKey(type) && _errors[type] == null) return;
    final api = context.read<ApiClient>();
    final sources = _selectedSources.toList();
    final generation = _searchGeneration;
    final query = _lastQuery;
    setState(() {
      _loadingTypes.add(type);
      _errors.remove(type);
    });
    try {
      final response = await api.search(
        query: query,
        type: type,
        sources: sources.isEmpty ? const ['netease'] : sources,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results[type] = response;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _errors[type] = error is ApiException ? error.message : '$error';
      });
    } finally {
      // A newer search owns the loading flag now; do not clear it here.
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _loadingTypes.remove(type);
        });
      }
    }
  }

  void _toggleSource(String id) {
    setState(() {
      if (_selectedSources.contains(id)) {
        if (_selectedSources.length > 1) _selectedSources.remove(id);
      } else {
        _selectedSources.add(id);
      }
    });
    if (_lastQuery.isNotEmpty) {
      setState(() {
        _searchGeneration++;
        _results.clear();
        _errors.clear();
        _loadingTypes.clear();
      });
      _searchType(_currentType);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final searchable = app.sources.where((e) => e.search).toList();
    if (!_sourcesInitialized && app.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initSources());
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchHeader(context),
            if (searchable.isNotEmpty)
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  itemCount: searchable.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final source = searchable[index];
                    final selected = _selectedSources.contains(source.id);
                    return FilterChip(
                      label: Text(source.name),
                      selected: selected,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? context.invertedFill : context.neutral(0.55),
                      ),
                      selectedColor: AppColors.accent.withValues(alpha: 0.24),
                      backgroundColor: context.neutral(0.045),
                      side: BorderSide.none,
                      onSelected: (_) => _toggleSource(source.id),
                    );
                  },
                ),
              ),
            TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorColor: AppColors.accent,
              dividerColor: Colors.transparent,
              labelColor: Theme.of(context).colorScheme.onSurface,
              unselectedLabelColor: context.neutral(0.42),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: '单曲'),
                Tab(text: '歌单'),
                Tab(text: '专辑'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final type in _searchTypes) _buildTypeTab(type),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      child: Row(
        children: [
          if (widget.showBack)
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              tooltip: '返回',
            )
          else
            const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: context.neutral(0.075),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: context.subtleBorder),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索歌曲、歌手、歌单或粘贴链接',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: context.neutral(0.45)),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: context.neutral(0.45)),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _lastQuery = '';
                            _results.clear();
                            _errors.clear();
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: '搜索',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              child: Ink(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF9C8FFF)]),
                ),
                child: InkWell(
                  onTap: () => _submit(_controller.text),
                  borderRadius: BorderRadius.circular(15),
                  child: const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTab(String type) {
    if (_lastQuery.isEmpty) {
      return _buildLanding();
    }
    if (_parsingLink) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    final error = _errors[type];
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '搜索失败',
        subtitle: error,
        action: FilledButton(onPressed: () => _searchType(type), child: const Text('重试')),
      );
    }
    final response = _results[type];
    if (response == null || _loadingTypes.contains(type)) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LoadingList(count: 7),
      );
    }
    return type == 'song' ? _buildSongResults(response) : _buildListResults(response, type);
  }

  Widget _buildLanding() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              const Text('最近搜索', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: _clearHistory,
                child: Text('清空', style: TextStyle(fontSize: 11.5, color: context.neutral(0.42))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _history)
                ActionChip(
                  label: Text(item),
                  avatar: Icon(Icons.history_rounded, size: 14, color: context.neutral(0.4)),
                  labelStyle: TextStyle(fontSize: 12, color: context.neutral(0.72)),
                  backgroundColor: context.neutral(0.055),
                  side: BorderSide.none,
                  onPressed: () {
                    _controller.text = item;
                    _submit(item);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        const Text('大家都在搜', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _suggestions)
              ActionChip(
                label: Text(item),
                labelStyle: const TextStyle(fontSize: 12),
                backgroundColor: context.neutral(0.05),
                side: BorderSide(color: context.subtleBorder),
                onPressed: () {
                  _controller.text = item;
                  _submit(item);
                },
              ),
          ],
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [AppColors.accent.withValues(alpha: 0.14), AppColors.accentAlt.withValues(alpha: 0.06)],
            ),
            border: Border.all(color: context.subtleBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '支持直接粘贴网易云、QQ 音乐、酷狗、酷我、B 站等平台链接',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: context.neutral(0.62)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongResults(SearchResponse response) {
    final groups = response.groups.where((g) => g.songs.isNotEmpty || g.error.isNotEmpty).toList();
    final total = response.groups.fold<int>(0, (sum, g) => sum + g.songs.length);
    if (total == 0) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到「$_lastQuery」',
        subtitle: groups.any((g) => g.error.isNotEmpty)
            ? groups.map((g) => g.error).where((e) => e.isNotEmpty).toSet().join('\n')
            : '换个关键词或切换更多音乐源试试',
      );
    }
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              '找到 $total 首歌曲 · ${response.tookMs}ms',
              style: TextStyle(fontSize: 11.5, color: context.neutral(0.48)),
            ),
          ),
        ),
        for (final group in groups)
          if (group.songs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    SourceBadge(name: group.name),
                    const SizedBox(width: 8),
                    Text('${group.songs.length} 首', style: TextStyle(fontSize: 10.5, color: context.neutral(0.45))),
                    if (group.error.isNotEmpty) ...[const Text(' · ', style: TextStyle(fontSize: 10.5)), Flexible(child: Text(group.error, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orangeAccent
                        : const Color(0xFFB45309))))],
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '播放本组',
                      onPressed: () => playSongList(context, group.songs, 0),
                      icon: Icon(
                        Icons.play_circle_outline_rounded,
                        size: 20,
                        color: context.neutral(0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: group.songs.length,
              itemBuilder: (context, index) {
                final song = group.songs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SongTile(
                    song: song,
                    queue: group.songs,
                    index: index,
                    dense: true,
                  ),
                );
              },
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildListResults(SearchResponse response, String type) {
    final groups = response.groups.where((g) => g.playlists.isNotEmpty || g.error.isNotEmpty).toList();
    final total = response.groups.fold<int>(0, (sum, g) => sum + g.playlists.length);
    if (total == 0) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: type == 'album' ? '没有找到相关专辑' : '没有找到相关歌单',
        subtitle: groups.any((g) => g.error.isNotEmpty)
            ? groups.map((g) => g.error).where((e) => e.isNotEmpty).toSet().join('\n')
            : '换个关键词或切换更多音乐源试试',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 6
            : width >= 880
                ? 5
                : width >= 640
                    ? 4
                    : width >= 430
                        ? 3
                        : 2;
        const spacing = 14.0;
        final tileWidth = (width - 32 - spacing * (columns - 1)) / columns;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '找到 $total 个${type == 'album' ? '专辑' : '歌单'} · ${response.tookMs}ms',
                  style: TextStyle(fontSize: 11.5, color: context.neutral(0.48)),
                ),
              ),
            ),
            for (final group in groups)
              if (group.playlists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        SourceBadge(name: group.name),
                        const SizedBox(width: 8),
                        Text('${group.playlists.length} 个${type == 'album' ? '专辑' : '歌单'}',
                            style: TextStyle(fontSize: 10.5, color: context.neutral(0.45))),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: 18,
                      childAspectRatio: tileWidth / (tileWidth + 52),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final playlist = group.playlists[index];
                        return PlaylistCard(
                          playlist: playlist,
                          width: tileWidth,
                          onTap: () => openPlaylist(context, playlist, type: type),
                        );
                      },
                      childCount: group.playlists.length,
                    ),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}
