import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/player_controller.dart';
import '../../core/storage_bridge.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.source,
    this.id = '',
    required this.name,
    this.cover = '',
    this.creator = '',
    this.description = '',
    this.trackCount = 0,
    this.initialSongs,
    this.type = 'playlist',
    this.extra,
  });

  final String source;
  final String id;
  final String name;
  final String cover;
  final String creator;
  final String description;
  final int trackCount;
  final List<Song>? initialSongs;
  final String type;
  final Map<String, String>? extra;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _songs = widget.initialSongs ?? const [];
    _loading = _songs.isEmpty;
    if (widget.id.isNotEmpty) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = widget.type == 'album' ? await api.album(widget.source, widget.id) : await api.playlist(widget.source, widget.id);
      if (!mounted) return;
      setState(() {
        _songs = detail.songs;
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
    final cover = app.api.coverUrl(widget.cover, source: widget.source);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth > 900;

    return Scaffold(
      bottomNavigationBar: player.hasSong ? const SafeArea(top: false, child: MiniPlayer()) : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverAppBar(
              expandedHeight: isWide ? 330 : 300,
              pinned: true,
              backgroundColor: const Color(0xFF0A0A11),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                ),
              ),
              actions: [
                IconButton(onPressed: () => _showCollectionActions(context, app), icon: const Icon(Icons.more_horiz_rounded)),
                const SizedBox(width: 6),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover.isNotEmpty)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                        child: Opacity(opacity: 0.5, child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x550A0A11), Color(0xCC0A0A11), Color(0xFF0A0A11)],
                          stops: [0, 0.68, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CoverArt(
                            url: cover,
                            size: isWide ? 170 : 118,
                            radius: 20,
                            seed: widget.name,
                            icon: widget.type == 'album' ? Icons.album_rounded : Icons.queue_music_rounded,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.type == 'album' ? '专辑' : '歌单',
                                  style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.5)),
                                ),
                                const SizedBox(height: 5),
                                Text(widget.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: isWide ? 30 : 21, fontWeight: FontWeight.w800, height: 1.16)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SourceBadge(name: app.sourceName(widget.source)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.creator.isEmpty ? '${_songs.length} 首歌曲' : '${widget.creator} · ${_songs.length} 首',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.48)),
                                      ),
                                    ),
                                  ],
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
            if (widget.description.trim().isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: _ExpandableText(text: widget.description),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _songs.isEmpty ? null : () => playSongList(context, _songs, 0),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('播放全部 (${_songs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: _songs.isEmpty
                          ? null
                          : () async {
                              try {
                                await app.downloadSongs(_songs);
                                if (context.mounted) showAppSnack(context, StorageBridge.queuedMessage);
                              } catch (error) {
                                if (context.mounted) showAppSnack(context, '$error');
                              }
                            },
                      icon: const Icon(Icons.download_rounded),
                      tooltip: '下载全部',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _songs.isEmpty ? null : () => _showAddAll(context, app),
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: '收藏歌单',
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: SizedBox(height: 320, child: LoadingList(count: 6)))
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: '加载失败',
                  subtitle: _error,
                  action: FilledButton(onPressed: _load, child: const Text('重试')),
                ),
              )
            else if (_songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.music_off_rounded, title: '暂无歌曲'),
              )
            else
              SliverList.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return SongTile(
                    song: song,
                    queue: _songs,
                    index: index,
                    selected: player.current?.key == song.key,
                    dense: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${index + 1}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25))),
                        const SizedBox(width: 4),
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
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Future<void> _showCollectionActions(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_check_rounded),
              title: const Text('添加全部到歌单'),
              onTap: () {
                Navigator.pop(sheet);
                _showAddAll(context, app);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('下载全部'),
              onTap: () async {
                Navigator.pop(sheet);
                await app.downloadSongs(_songs);
                if (context.mounted) showAppSnack(context, StorageBridge.queuedMessage);
              },
            ),
            if (widget.type == 'playlist' && widget.id.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('在浏览器中打开'),
                onTap: () {
                  Navigator.pop(sheet);
                },
              ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddAll(BuildContext context, AppState app) async {
    if (_songs.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('收藏到歌单', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ),
            for (final collection in app.collections)
              ListTile(
                leading: Icon(collection.isFavorites ? Icons.favorite_rounded : Icons.queue_music_rounded,
                    color: collection.isFavorites ? AppColors.accentAlt : null),
                title: Text(collection.name),
                subtitle: Text('${collection.songs.length} 首'),
                onTap: () async {
                  await app.addToCollection(collection.id, _songs);
                  if (sheet.mounted) Navigator.pop(sheet);
                  if (context.mounted) showAppSnack(context, '已添加到「${collection.name}」');
                },
              ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? null : TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white.withValues(alpha: 0.42)),
      ),
    );
  }
}
