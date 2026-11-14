import 'package:flutter/foundation.dart';

@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.artist,
    this.album = '',
    this.albumId = '',
    this.duration = 0,
    this.size = 0,
    this.bitrate = 0,
    this.source = '',
    this.url = '',
    this.ext = '',
    this.cover = '',
    this.link = '',
    this.extra = const {},
    this.isVip = false,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String albumId;
  final int duration;
  final int size;
  final int bitrate;
  final String source;
  final String url;
  final String ext;
  final String cover;
  final String link;
  final Map<String, String> extra;
  final bool isVip;

  String get key => '$source:$id';

  String get durationText {
    if (duration <= 0) return '--:--';
    final m = duration ~/ 60;
    final s = duration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    final rawExtra = json['extra'];
    final extra = <String, String>{};
    if (rawExtra is Map) {
      rawExtra.forEach((key, value) {
        if (value != null) extra['$key'] = '$value';
      });
    }
    return Song(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? '未知歌曲'}',
      artist: '${json['artist'] ?? '未知歌手'}',
      album: '${json['album'] ?? ''}',
      albumId: '${json['album_id'] ?? ''}',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
      source: '${json['source'] ?? ''}',
      url: '${json['url'] ?? ''}',
      ext: '${json['ext'] ?? ''}',
      cover: '${json['cover'] ?? ''}',
      link: '${json['link'] ?? ''}',
      extra: extra,
      isVip: json['is_vip'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artist': artist,
        'album': album,
        'album_id': albumId,
        'duration': duration,
        'size': size,
        'bitrate': bitrate,
        'source': source,
        'url': url,
        'ext': ext,
        'cover': cover,
        'link': link,
        'extra': extra,
        'is_vip': isVip,
      };

  @override
  bool operator ==(Object other) => other is Song && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.cover = '',
    this.trackCount = 0,
    this.playCount = 0,
    this.creator = '',
    this.description = '',
    this.source = '',
    this.link = '',
    this.extra = const {},
  });

  final String id;
  final String name;
  final String cover;
  final int trackCount;
  final int playCount;
  final String creator;
  final String description;
  final String source;
  final String link;
  final Map<String, String> extra;

  String get key => '$source:$id';

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawExtra = json['extra'];
    final extra = <String, String>{};
    if (rawExtra is Map) {
      rawExtra.forEach((key, value) {
        if (value != null) extra['$key'] = '$value';
      });
    }
    return Playlist(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? '未命名歌单'}',
      cover: '${json['cover'] ?? ''}',
      trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
      creator: '${json['creator'] ?? ''}',
      description: '${json['description'] ?? ''}',
      source: '${json['source'] ?? ''}',
      link: '${json['link'] ?? ''}',
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cover': cover,
        'track_count': trackCount,
        'play_count': playCount,
        'creator': creator,
        'description': description,
        'source': source,
        'link': link,
        'extra': extra,
      };
}

@immutable
class TopList {
  const TopList({
    required this.id,
    required this.name,
    this.cover = '',
    this.description = '',
    this.updateFrequency = '',
    this.trackCount = 0,
    this.source = '',
    this.link = '',
  });

  final String id;
  final String name;
  final String cover;
  final String description;
  final String updateFrequency;
  final int trackCount;
  final String source;
  final String link;

  factory TopList.fromJson(Map<String, dynamic> json) => TopList(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        description: '${json['description'] ?? ''}',
        updateFrequency: '${json['update_frequency'] ?? ''}',
        trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
        source: '${json['source'] ?? ''}',
        link: '${json['link'] ?? ''}',
      );
}

@immutable
class PlaylistCategory {
  const PlaylistCategory({
    required this.id,
    required this.name,
    this.group = '',
    this.source = '',
    this.count = 0,
    this.hot = false,
  });

  final String id;
  final String name;
  final String group;
  final String source;
  final int count;
  final bool hot;

  factory PlaylistCategory.fromJson(Map<String, dynamic> json) => PlaylistCategory(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        group: '${json['group'] ?? ''}',
        source: '${json['source'] ?? ''}',
        count: (json['count'] as num?)?.toInt() ?? 0,
        hot: json['hot'] == true,
      );
}

class TopListGroup {
  const TopListGroup({required this.source, required this.name, this.lists = const [], this.error = ''});

  final String source;
  final String name;
  final List<TopList> lists;
  final String error;

  factory TopListGroup.fromJson(Map<String, dynamic> json) => TopListGroup(
        source: '${json['source'] ?? ''}',
        name: '${json['name'] ?? ''}',
        lists: (json['lists'] as List? ?? const [])
            .map((e) => TopList.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        error: '${json['error'] ?? ''}',
      );
}

class CategoryGroup {
  const CategoryGroup({required this.source, required this.name, this.categories = const [], this.error = ''});

  final String source;
  final String name;
  final List<PlaylistCategory> categories;
  final String error;

  factory CategoryGroup.fromJson(Map<String, dynamic> json) => CategoryGroup(
        source: '${json['source'] ?? ''}',
        name: '${json['name'] ?? ''}',
        categories: (json['categories'] as List? ?? const [])
            .map((e) => PlaylistCategory.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        error: '${json['error'] ?? ''}',
      );
}

class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    this.search = false,
    this.playlist = false,
    this.album = false,
    this.topList = false,
    this.category = false,
    this.recommend = false,
    this.userPlaylist = false,
    this.qrLogin = false,
    this.note = '',
  });

  final String id;
  final String name;
  final bool search;
  final bool playlist;
  final bool album;
  final bool topList;
  final bool category;
  final bool recommend;
  final bool userPlaylist;
  final bool qrLogin;
  final String note;

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        search: json['search'] == true,
        playlist: json['playlist'] == true,
        album: json['album'] == true,
        topList: json['topList'] == true,
        category: json['category'] == true,
        recommend: json['recommend'] == true,
        userPlaylist: json['userPlaylist'] == true,
        qrLogin: json['qrLogin'] == true,
        note: '${json['note'] ?? ''}',
      );
}

class SourceResult {
  const SourceResult({
    required this.source,
    required this.name,
    this.songs = const [],
    this.playlists = const [],
    this.error = '',
    this.tookMs = 0,
  });

  final String source;
  final String name;
  final List<Song> songs;
  final List<Playlist> playlists;
  final String error;
  final int tookMs;

  factory SourceResult.fromJson(Map<String, dynamic> json) => SourceResult(
        source: '${json['source'] ?? ''}',
        name: '${json['name'] ?? ''}',
        songs: (json['songs'] as List? ?? const [])
            .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        playlists: (json['playlists'] as List? ?? const [])
            .map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        error: '${json['error'] ?? ''}',
        tookMs: (json['tookMs'] as num?)?.toInt() ?? 0,
      );
}

class SearchResponse {
  const SearchResponse({this.groups = const [], this.total = 0, this.tookMs = 0});

  final List<SourceResult> groups;
  final int total;
  final int tookMs;

  List<Song> get songs => groups.expand((g) => g.songs).toList();
  List<Playlist> get playlists => groups.expand((g) => g.playlists).toList();

  factory SearchResponse.fromJson(Map<String, dynamic> json) => SearchResponse(
        groups: (json['groups'] as List? ?? const [])
            .map((e) => SourceResult.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        tookMs: (json['tookMs'] as num?)?.toInt() ?? 0,
      );
}

class DetailResponse {
  const DetailResponse({this.type = '', this.playlist, this.song, this.songs = const []});

  final String type;
  final Playlist? playlist;
  final Song? song;
  final List<Song> songs;

  factory DetailResponse.fromJson(Map<String, dynamic> json) => DetailResponse(
        type: '${json['type'] ?? ''}',
        playlist: json['playlist'] is Map ? Playlist.fromJson((json['playlist'] as Map).cast<String, dynamic>()) : null,
        song: json['song'] is Map ? Song.fromJson((json['song'] as Map).cast<String, dynamic>()) : null,
        songs: (json['songs'] as List? ?? const [])
            .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.cover = '',
    this.isFavorites = false,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String cover;
  final bool isFavorites;
  final List<Song> songs;

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        isFavorites: json['isFavorites'] == true,
        songs: (json['songs'] as List? ?? const [])
            .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.name,
    this.artist = '',
    this.album = '',
    this.cover = '',
    this.source = '',
    this.status = 'waiting',
    this.error = '',
    this.path = '',
    this.total = 0,
    this.received = 0,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String cover;
  final String source;
  final String status;
  final String error;
  final String path;
  final int total;
  final int received;

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        artist: '${json['artist'] ?? ''}',
        album: '${json['album'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        source: '${json['source'] ?? ''}',
        status: '${json['status'] ?? 'waiting'}',
        error: '${json['error'] ?? ''}',
        path: '${json['path'] ?? ''}',
        total: (json['total'] as num?)?.toInt() ?? 0,
        received: (json['received'] as num?)?.toInt() ?? 0,
      );
}

class AppSettings {
  const AppSettings({
    this.downloadDir = '',
    this.filenameTemplate = '{artist} - {name}',
    this.defaultSearch = const [],
    this.themeMode = 'system',
  });

  final String downloadDir;
  final String filenameTemplate;
  final List<String> defaultSearch;
  final String themeMode;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        downloadDir: '${json['downloadDir'] ?? ''}',
        filenameTemplate: '${json['filenameTemplate'] ?? '{artist} - {name}'}',
        defaultSearch: (json['defaultSearchSources'] as List? ?? const []).map((e) => '$e').toList(),
        themeMode: '${json['themeMode'] ?? 'system'}',
      );
}
