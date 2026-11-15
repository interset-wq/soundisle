import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

class PlayInfo {
  const PlayInfo({
    required this.url,
    this.ext = '',
    this.preview = false,
    this.fallbackSource = '',
    this.fallbackName = '',
    this.fallbackArtist = '',
  });

  final String url;
  final String ext;
  final bool preview;

  /// Set when the requested platform could not serve the track and another
  /// platform was used automatically.
  final String fallbackSource;
  final String fallbackName;
  final String fallbackArtist;

  bool get fallback => fallbackSource.isNotEmpty;
}

class QrSession {
  const QrSession({required this.key, this.imageUrl = '', this.url = ''});

  final String key;
  final String imageUrl;
  final String url;
}

class QrStatus {
  const QrStatus({required this.status, this.message = ''});

  final String status;
  final String message;

  bool get success => status == 'success';
  bool get terminal => success || status == 'expired' || status == 'failed';
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'X-Music-Token': token,
        'Accept': 'application/json',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final values = <String, String>{};
    query?.forEach((key, value) {
      if (value == null) return;
      if (value is Iterable) {
        if (value.isEmpty) return;
        values[key] = value.map((e) => '$e').join(',');
      } else {
        values[key] = '$value';
      }
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: values.isEmpty ? null : values);
  }

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? query, Object? body, Duration timeout = const Duration(seconds: 45)}) async {
    final uri = _uri(path, query);
    late http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await _client
              .post(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
              .timeout(timeout);
        case 'PUT':
          response = await _client
              .put(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
              .timeout(timeout);
        case 'PATCH':
          response = await _client
              .patch(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
              .timeout(timeout);
        case 'DELETE':
          response = await _client.delete(uri, headers: _headers).timeout(timeout);
        default:
          response = await _client.get(uri, headers: _headers).timeout(timeout);
      }
    } catch (error) {
      throw ApiException(0, '无法连接音乐核心：$error');
    }
    final text = utf8.decode(response.bodyBytes);
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] != null ? '${decoded['error']}' : '请求失败 (${response.statusCode})';
      throw ApiException(response.statusCode, message);
    }
    return decoded;
  }

  Future<({List<SourceInfo> sources, List<String> defaults})> fetchSources() async {
    final json = await _request('GET', '/api/sources') as Map<String, dynamic>;
    final sources = (json['sources'] as List? ?? const [])
        .map((e) => SourceInfo.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final defaults = (json['defaults'] as List? ?? const []).map((e) => '$e').toList();
    return (sources: sources, defaults: defaults);
  }

  Future<AppSettings> fetchSettings() async {
    final json = await _request('GET', '/api/settings') as Map<String, dynamic>;
    return AppSettings.fromJson(json);
  }

  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    final json = await _request('PUT', '/api/settings', body: patch) as Map<String, dynamic>;
    return AppSettings.fromJson(json);
  }

  Future<SearchResponse> search({
    required String query,
    required String type,
    required List<String> sources,
    int limit = 30,
  }) async {
    final json = await _request('GET', '/api/search', query: {
      'q': query,
      'type': type,
      'sources': sources,
      'limit': limit,
    }, timeout: const Duration(seconds: 40)) as Map<String, dynamic>;
    return SearchResponse.fromJson(json);
  }

  Future<DetailResponse> playlist(String source, String id) async {
    final json = await _request('GET', '/api/playlist', query: {'source': source, 'id': id}) as Map<String, dynamic>;
    return DetailResponse.fromJson(json);
  }

  Future<DetailResponse> album(String source, String id) async {
    final json = await _request('GET', '/api/album', query: {'source': source, 'id': id}) as Map<String, dynamic>;
    return DetailResponse.fromJson(json);
  }

  Future<DetailResponse> parseLink(String link) async {
    final json = await _request('GET', '/api/parse', query: {'url': link}, timeout: const Duration(seconds: 60)) as Map<String, dynamic>;
    return DetailResponse.fromJson(json);
  }

  Future<List<TopListGroup>> topLists({List<String> sources = const []}) async {
    final json = await _request('GET', '/api/toplists', query: {
      'sources': sources,
    }, timeout: const Duration(seconds: 45)) as Map<String, dynamic>;
    return (json['groups'] as List? ?? const [])
        .map((e) => TopListGroup.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<CategoryGroup>> categories({List<String> sources = const []}) async {
    final json = await _request('GET', '/api/categories', query: {
      'sources': sources,
    }, timeout: const Duration(seconds: 45)) as Map<String, dynamic>;
    return (json['groups'] as List? ?? const [])
        .map((e) => CategoryGroup.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Song>> toplistSongs(String source, String id) async {
    final json = await _request('GET', '/api/toplist', query: {'source': source, 'id': id}) as Map<String, dynamic>;
    return (json['songs'] as List? ?? const [])
        .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Playlist>> categoryPlaylists(String source, String id, {int page = 1, int limit = 30}) async {
    final json = await _request('GET', '/api/category', query: {
      'source': source,
      'id': id,
      'page': page,
      'limit': limit,
    }) as Map<String, dynamic>;
    return (json['playlists'] as List? ?? const [])
        .map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Playlist>> recommend(String source) async {
    final json = await _request('GET', '/api/recommend', query: {'source': source}, timeout: const Duration(seconds: 30)) as Map<String, dynamic>;
    return (json['playlists'] as List? ?? const [])
        .map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Song>> hotSongs(String source, {int limit = 20}) async {
    final json = await _request('GET', '/api/hot', query: {'source': source, 'limit': limit}) as Map<String, dynamic>;
    return (json['songs'] as List? ?? const [])
        .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Playlist>> userPlaylists(String source) async {
    final json = await _request('GET', '/api/user_playlists', query: {'source': source}) as Map<String, dynamic>;
    return (json['playlists'] as List? ?? const [])
        .map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> lyric(Song song) async {
    final json = await _request('POST', '/api/lyric', body: {'song': song.toJson()}, timeout: const Duration(seconds: 30)) as Map<String, dynamic>;
    return '${json['lrc'] ?? ''}';
  }

  Future<PlayInfo> play(Song song) async {
    final json = await _request('POST', '/api/play', body: {'song': song.toJson()}, timeout: const Duration(minutes: 4)) as Map<String, dynamic>;
    final path = '${json['url'] ?? ''}';
    if (path.isEmpty) throw ApiException(0, '平台没有返回可播放地址');
    return PlayInfo(
      url: '$baseUrl$path',
      ext: '${json['ext'] ?? ''}',
      preview: json['preview'] == true,
      fallbackSource: '${json['resolvedSource'] ?? ''}',
      fallbackName: '${json['resolvedName'] ?? ''}',
      fallbackArtist: '${json['resolvedArtist'] ?? ''}',
    );
  }

  Future<List<Collection>> collections() async {
    final json = await _request('GET', '/api/collections') as Map<String, dynamic>;
    return (json['collections'] as List? ?? const [])
        .map((e) => Collection.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Collection> collection(String id) async {
    final json = await _request('GET', '/api/collections/$id') as Map<String, dynamic>;
    return Collection.fromJson(json);
  }

  Future<Collection> createCollection(String name) async {
    final json = await _request('POST', '/api/collections', body: {'name': name}) as Map<String, dynamic>;
    return Collection.fromJson(json);
  }

  Future<Collection> renameCollection(String id, String name) async {
    final json = await _request('PATCH', '/api/collections/$id', body: {'name': name}) as Map<String, dynamic>;
    return Collection.fromJson(json);
  }

  Future<void> deleteCollection(String id) => _request('DELETE', '/api/collections/$id');

  Future<Collection> addSongs(String id, List<Song> songs) async {
    final json = await _request('POST', '/api/collections/$id/songs',
        body: {'songs': songs.map((e) => e.toJson()).toList()}) as Map<String, dynamic>;
    return Collection.fromJson(json);
  }

  Future<Collection> removeSong(String id, Song song) async {
    final json = await _request('DELETE', '/api/collections/$id/songs', query: {
      'source': song.source,
      'id': song.id,
    }) as Map<String, dynamic>;
    return Collection.fromJson(json);
  }

  Future<List<Song>> library({String query = ''}) async {
    final json = await _request('GET', '/api/library', query: {'q': query, 'limit': 500}) as Map<String, dynamic>;
    return (json['songs'] as List? ?? const [])
        .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<Song>> rescanLibrary() async {
    final json = await _request('POST', '/api/library/scan', timeout: const Duration(seconds: 90)) as Map<String, dynamic>;
    return (json['songs'] as List? ?? const [])
        .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> deleteLocalSong(Song song) async {
    final path = song.extra['path'] ?? '';
    if (path.isEmpty) return;
    await _request('DELETE', '/api/library', query: {'path': path});
  }

  Future<List<DownloadTask>> downloads() async {
    final json = await _request('GET', '/api/downloads') as Map<String, dynamic>;
    return (json['tasks'] as List? ?? const [])
        .map((e) => DownloadTask.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> download(List<Song> songs) async {
    await _request('POST', '/api/download', body: {'songs': songs.map((e) => e.toJson()).toList()});
  }

  Future<void> removeDownload(String id) => _request('DELETE', '/api/downloads/$id');

  Future<Map<String, String>> cookies() async {
    final json = await _request('GET', '/api/cookies') as Map<String, dynamic>;
    final raw = json['cookies'];
    if (raw is! Map) return {};
    return raw.map((key, value) => MapEntry('$key', '$value'));
  }

  Future<void> setCookie(String source, String value) async {
    await _request('PUT', '/api/cookies', body: {'source': source, 'value': value});
  }

  Future<QrSession> loginCreate(String source, {String type = ''}) async {
    final json = await _request('POST', '/api/login/$source/create', query: {
      if (type.isNotEmpty) 'type': type,
    }, timeout: const Duration(seconds: 30)) as Map<String, dynamic>;
    return QrSession(key: '${json['key'] ?? ''}', imageUrl: '${json['imageUrl'] ?? ''}', url: '${json['url'] ?? ''}');
  }

  Future<QrStatus> loginCheck(String source, String key, {String type = ''}) async {
    final json = await _request('GET', '/api/login/$source/check', query: {
      'key': key,
      if (type.isNotEmpty) 'type': type,
    }) as Map<String, dynamic>;
    return QrStatus(status: '${json['status'] ?? ''}', message: '${json['message'] ?? ''}');
  }

  String coverUrl(String? raw, {String source = ''}) {
    if (raw == null || raw.trim().isEmpty) return '';
    if (raw.startsWith('/api/library/cover')) {
      final separator = raw.contains('?') ? '&' : '?';
      return '$baseUrl$raw${separator}token=$token';
    }
    if (raw.startsWith('/api/')) {
      final separator = raw.contains('?') ? '&' : '?';
      return '$baseUrl$raw${separator}token=$token';
    }
    return '$baseUrl/api/cover?url=${Uri.encodeQueryComponent(raw)}&source=$source&token=$token';
  }

  void close() => _client.close();
}
