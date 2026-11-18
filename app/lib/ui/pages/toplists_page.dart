import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

class TopListsPage extends StatefulWidget {
  const TopListsPage({super.key});

  @override
  State<TopListsPage> createState() => _TopListsPageState();
}

class _TopListsPageState extends State<TopListsPage> {
  String _source = 'netease';
  List<TopList> _lists = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await api.topLists(sources: [_source]);
      final group = groups.firstWhere(
        (e) => e.source == _source,
        orElse: () => const TopListGroup(source: '', name: ''),
      );
      if (!mounted) return;
      setState(() {
        _lists = group.lists;
        _error = group.error.isEmpty ? null : group.error;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final sources = app.sources.where((e) => e.topList).toList();
    if (sources.isNotEmpty && !sources.any((e) => e.id == _source)) {
      _source = sources.first.id;
    }
    return Scaffold(
      bottomNavigationBar: player.hasSong
          ? const SafeArea(top: false, child: MiniPlayer())
          : null,
      appBar: AppBar(
        title: const Text('排行榜', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: sources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final source = sources[index];
                final selected = source.id == _source;
                return ChoiceChip(
                  label: Text(source.name),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? context.invertedFill
                        : context.neutral(0.55),
                  ),
                  selectedColor: AppColors.accent.withValues(alpha: 0.25),
                  backgroundColor: context.neutral(0.05),
                  side: BorderSide.none,
                  onSelected: (_) {
                    setState(() => _source = source.id);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const LoadingList(count: 8)
                  : _error != null
                  ? EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: '加载失败',
                      subtitle: _error,
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    )
                  : _lists.isEmpty
                  ? const EmptyState(
                      icon: Icons.leaderboard_outlined,
                      title: '暂无榜单',
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _lists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final topList = _lists[index];
                        return _TopListRow(
                          topList: topList,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  TopListSongsPage(topList: topList),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopListRow extends StatelessWidget {
  const _TopListRow({required this.topList, this.onTap});

  final TopList topList;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cover = app.api.coverUrl(topList.cover, source: topList.source);
    return Material(
      color: context.neutral(0.04),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CoverArt(
                url: cover,
                size: 70,
                radius: 14,
                seed: topList.name,
                icon: Icons.leaderboard_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topList.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (topList.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        topList.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.neutral(0.4),
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SourceBadge(
                          name: app.sourceName(topList.source),
                          dense: true,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          topList.updateFrequency.isEmpty
                              ? '${topList.trackCount} 首'
                              : topList.updateFrequency,
                          style: TextStyle(
                            fontSize: 10,
                            color: context.neutral(0.34),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.neutral(0.25)),
            ],
          ),
        ),
      ),
    );
  }
}

class TopListSongsPage extends StatefulWidget {
  const TopListSongsPage({super.key, required this.topList});

  final TopList topList;

  @override
  State<TopListSongsPage> createState() => _TopListSongsPageState();
}

class _TopListSongsPageState extends State<TopListSongsPage> {
  List<Song> _songs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await api.toplistSongs(
        widget.topList.source,
        widget.topList.id,
      );
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final topList = widget.topList;
    final cover = app.api.coverUrl(topList.cover, source: topList.source);
    return Scaffold(
      bottomNavigationBar: player.hasSong
          ? const SafeArea(top: false, child: MiniPlayer())
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover.isNotEmpty)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Opacity(
                          opacity:
                              Theme.of(context).brightness == Brightness.dark
                              ? 0.45
                              : 0.3,
                          child: CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const SizedBox(),
                          ),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).scaffoldBackgroundColor
                                .withValues(alpha: 0.27),
                            Theme.of(context).scaffoldBackgroundColor
                                .withValues(alpha: 0.93),
                            Theme.of(context).scaffoldBackgroundColor,
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
                            radius: 20,
                            seed: topList.name,
                            icon: Icons.leaderboard_rounded,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '排行榜',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  topList.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${app.sourceName(topList.source)} · ${topList.updateFrequency.isEmpty ? '${_songs.length} 首' : topList.updateFrequency}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.neutral(0.45),
                                  ),
                                ),
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
            if (_loading)
              const SliverToBoxAdapter(
                child: SizedBox(height: 360, child: LoadingList(count: 8)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: '加载失败',
                  subtitle: _error,
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('重试'),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _songs.isEmpty
                              ? null
                              : () => playSongList(context, _songs, 0),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.invertedFill,
                            foregroundColor: context.invertedInk,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            '播放全部 (${_songs.length})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: _songs.isEmpty
                            ? null
                            : () async {
                                final result = await app.downloadSongs(_songs);
                                if (context.mounted) {
                                  showAppSnack(
                                    context,
                                    app.describeDownloadEnqueue(result),
                                  );
                                }
                              },
                        icon: const Icon(Icons.download_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  final rank = song.extra['rank'] ?? '${index + 1}';
                  return SongTile(
                    song: song,
                    queue: _songs,
                    index: index,
                    dense: true,
                    selected: player.current?.key == song.key,
                    playing: player.playing && player.current?.key == song.key,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            rank,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: index < 3 ? 14 : 11,
                              fontWeight: index < 3
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: index < 3
                                  ? AppColors.accent
                                  : context.neutral(0.28),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 19,
                            color: context.neutral(0.4),
                          ),
                          onPressed: () => showSongActions(context, song),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ),
      ),
    );
  }
}
