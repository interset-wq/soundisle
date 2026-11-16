import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';
import 'toplists_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenSearch, required this.onOpenLibrary});

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _recommendSources = ['netease', 'qq', 'kugou'];

  List<Playlist> _recommend = const [];
  List<Song> _hot = const [];
  List<TopList> _topLists = const [];
  bool _loading = true;
  bool _recommendLoading = false;
  int _recommendCursor = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Refreshes only the recommendation strip. "换一批" must not clear the rest
  /// of the home page or replace it with a full-page spinner.
  Future<void> _refreshRecommend() async {
    if (_recommendLoading) return;
    setState(() => _recommendLoading = true);
    final api = context.read<ApiClient>();
    List<Playlist> next = const [];
    var cursor = _recommendCursor;
    for (var attempt = 0; attempt < _recommendSources.length; attempt++) {
      final index = (cursor + attempt) % _recommendSources.length;
      try {
        final items = await api.recommend(_recommendSources[index]);
        if (items.isNotEmpty) {
          next = items;
          cursor = (index + 1) % _recommendSources.length;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      if (next.isNotEmpty) _recommend = next;
      _recommendCursor = cursor;
      _recommendLoading = false;
    });
    if (next.isEmpty) {
      showAppSnack(context, '暂时没有更多推荐，请稍后再试');
    }
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    List<Playlist> recommend = const [];
    List<Song> hot = const [];
    List<TopList> topLists = const [];

    try {
      recommend = await api.recommend('netease');
      _recommendCursor = 1 % _recommendSources.length;
    } catch (_) {
      try {
        recommend = await api.recommend('qq');
        _recommendCursor = 2 % _recommendSources.length;
      } catch (_) {}
    }
    try {
      hot = await api.hotSongs('netease', limit: 20);
    } catch (_) {
      try {
        hot = await api.hotSongs('qq', limit: 20);
      } catch (_) {}
    }
    try {
      final groups = await api.topLists(sources: const ['netease']);
      topLists = groups.expand((e) => e.lists).take(8).toList();
    } catch (_) {
      try {
        final groups = await api.topLists(sources: const ['qq']);
        topLists = groups.expand((e) => e.lists).take(8).toList();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recommend = recommend;
      _hot = hot;
      _topLists = topLists;
      _loading = false;
      if (recommend.isEmpty && hot.isEmpty && topLists.isEmpty) {
        _error = '网络连接失败，请检查网络后下拉刷新';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final local = app.localSongs.take(6).toList();
    final rows = <Widget>[
      if (_recommend.isNotEmpty) ...[
        SectionHeader(
          title: '为你推荐',
          subtitle: '根据热门趋势挑选',
          action: _recommendLoading ? '加载中…' : '换一批',
          onAction: _refreshRecommend,
        ),
        SizedBox(
          height: 222,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _recommend.length.clamp(0, 20),
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = _recommend[index];
              return PlaylistCard(
                playlist: playlist,
                width: 142,
                onTap: () => openPlaylist(context, playlist),
              );
            },
          ),
        ),
      ],
      if (_hot.isNotEmpty) ...[
        SectionHeader(
          title: '热门单曲',
          subtitle: '此刻大家都在听',
          action: '播放全部',
          onAction: () => playSongList(context, _hot, 0),
        ),
        ..._hot.take(8).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final song = entry.value;
          return SongTile(
            song: song,
            queue: _hot,
            index: index,
            selected: player.current?.key == song.key,
            dense: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${index + 1}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25))),
                const SizedBox(width: 2),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_horiz_rounded, size: 19, color: Colors.white.withValues(alpha: 0.4)),
                  onPressed: () => showSongActions(context, song),
                ),
              ],
            ),
          );
        }),
      ],
      if (_topLists.isNotEmpty) ...[
        SectionHeader(
          title: '排行榜',
          subtitle: '实时更新的热门榜单',
          action: '全部榜单',
          onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TopListsPage())),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _topLists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final topList = _topLists[index];
              return TopListCard(
                topList: topList,
                width: 208,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TopListSongsPage(topList: topList),
                )),
              );
            },
          ),
        ),
      ],
      if (local.isNotEmpty) ...[
        SectionHeader(
          title: '本地音乐',
          subtitle: '已下载 ${app.localSongs.length} 首',
          action: '查看全部',
          onAction: widget.onOpenLibrary,
        ),
        ...local.take(4).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final song = entry.value;
          return SongTile(
            song: song,
            queue: app.localSongs,
            index: index,
            dense: true,
            showSource: false,
            selected: player.current?.key == song.key,
          );
        }),
      ],
      const SizedBox(height: 30),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _hero(context, app)),
          if (_loading)
            const SliverToBoxAdapter(child: SizedBox(height: 420, child: LoadingList(count: 6)))
          else if (_error != null)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 320,
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: '加载失败',
                  subtitle: _error,
                  action: FilledButton(onPressed: _load, child: const Text('重试')),
                ),
              ),
            )
          else
            SliverList(delegate: SliverChildListDelegate(rows)),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, AppState app) {
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
            ? '早上好'
            : hour < 18
                ? '下午好'
                : '晚上好';
    return SizedBox(
      height: 230,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF241D4F), Color(0xFF12101F), Color(0xFF0A0A11)],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned(
            right: -60,
            top: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppColors.accent.withValues(alpha: 0.5), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -90,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppColors.accentAlt.withValues(alpha: 0.26), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentAlt]),
                        ),
                        child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 19),
                      ),
                      const SizedBox(width: 10),
                      const Text('声屿', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      const Spacer(),
                      Text('${app.localSongs.length} 首本地歌曲',
                          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35))),
                    ],
                  ),
                  const Spacer(),
                  Text(greeting, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: 6),
                  Text('想听点什么？', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.48))),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onOpenSearch,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 21, color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('搜索歌曲、歌手、歌单或粘贴链接',
                                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('全网', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
