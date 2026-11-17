import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'storage_bridge.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;

  List<SourceInfo> sources = const [];
  List<String> defaultSources = const [];
  AppSettings settings = const AppSettings();
  List<Collection> collections = const [];
  List<Song> localSongs = const [];
  List<DownloadTask> downloads = const [];
  bool ready = false;
  bool scanning = false;
  String? lastError;
  Timer? _downloadTimer;
  bool _pollingDownloads = false;

  /// Whether tapping a song opens the full now-playing page right away.
  /// Purely a UI preference, so it lives in shared_preferences instead of the
  /// backend settings file.
  bool tapSongOpensPlayer = true;
  static const _prefTapSongOpensPlayer = 'ui.tap_song_opens_player';

  /// Recently played songs, newest first. Persisted locally so the home page
  /// can offer "继续听" without an account.
  List<Song> recentSongs = const [];
  static const _prefRecentSongs = 'library.recent_songs';
  static const _recentLimit = 50;

  Future<void> _loadUiPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      tapSongOpensPlayer = prefs.getBool(_prefTapSongOpensPlayer) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadRecentSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefRecentSongs) ?? const [];
      final songs = <Song>[];
      for (final item in stored) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map) {
            songs.add(Song.fromJson(decoded.cast<String, dynamic>()));
          }
        } catch (_) {}
      }
      recentSongs = songs;
      notifyListeners();
    } catch (_) {}
  }

  /// Called whenever a track starts, including auto-advance.
  Future<void> recordPlayed(Song song) async {
    final next = <Song>[
      song,
      ...recentSongs.where((e) => e.key != song.key),
    ].take(_recentLimit).toList();
    recentSongs = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefRecentSongs,
        [for (final item in next) jsonEncode(item.toJson())],
      );
    } catch (_) {}
  }

  Future<void> setTapSongOpensPlayer(bool value) async {
    tapSongOpensPlayer = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefTapSongOpensPlayer, value);
    } catch (_) {}
  }

  /// Task id -> where the exported copy lives (Android only).
  final Map<String, String> exportedLocations = {};
  final Map<String, String> exportErrors = {};
  final Set<String> _exportedTasks = {};

  Collection? get favorites {
    for (final collection in collections) {
      if (collection.isFavorites) return collection;
    }
    return null;
  }

  Set<String> get favoriteKeys => favorites?.songs.map((e) => e.key).toSet() ?? <String>{};

  SourceInfo? sourceInfo(String id) {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  String sourceName(String id) => sourceInfo(id)?.name ?? id;

  Future<void> initialize() async {
    unawaited(_loadUiPrefs());
    unawaited(_loadRecentSongs());
    final results = await Future.wait([
      api.fetchSources(),
      api.fetchSettings(),
      api.collections(),
      api.library(),
    ]);
    final sourceResult = results[0] as ({List<SourceInfo> sources, List<String> defaults});
    sources = sourceResult.sources;
    defaultSources = sourceResult.defaults;
    settings = results[1] as AppSettings;
    collections = results[2] as List<Collection>;
    localSongs = results[3] as List<Song>;
    if (settings.defaultSearch.isNotEmpty) defaultSources = settings.defaultSearch;
    ready = true;
    notifyListeners();
    unawaited(refreshDownloads());
  }

  Future<void> refreshCollections() async {
    collections = await api.collections();
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    localSongs = await api.library();
    notifyListeners();
  }

  Future<void> rescanLibrary() async {
    scanning = true;
    notifyListeners();
    try {
      localSongs = await api.rescanLibrary();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// Removes several downloaded files and refreshes the local list.
  Future<int> deleteLocalSongs(List<Song> songs) async {
    if (songs.isEmpty) return 0;
    final deleted = await api.deleteLocalSongs(songs);
    await refreshLibrary();
    return deleted;
  }

  /// True while `Music/声屿` is being copied back into the private library.
  bool importingExported = false;

  /// Restores local music from the shared `Music/声屿` folder, e.g. after a
  /// reinstall wiped the app-private download directory.
  Future<ImportSummary?> importExportedMusic() async {
    if (!StorageBridge.supported) return null;
    final dir = settings.downloadDir;
    if (dir.isEmpty) return null;
    importingExported = true;
    notifyListeners();
    try {
      final summary = await StorageBridge.importExported(dir: dir);
      if (summary != null && summary.imported > 0) {
        await rescanLibrary();
      }
      return summary;
    } finally {
      importingExported = false;
      notifyListeners();
    }
  }

  Future<void> refreshDownloads() async {
    downloads = await api.downloads();
    _syncDownloadPolling();
    notifyListeners();
    unawaited(_exportFinishedDownloads());
  }

  /// True while a download or asset repair is still running.
  bool get hasActiveDownloads => downloads.any(
    (task) =>
        task.status == 'waiting' ||
        task.status == 'downloading' ||
        task.repairing,
  );

  /// Polls only while something is running. A permanent 2s timer kept waking
  /// the CPU and hitting the local API even when the download list was idle.
  void _syncDownloadPolling() {
    if (hasActiveDownloads) {
      _downloadTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollDownloads(),
      );
    } else {
      _downloadTimer?.cancel();
      _downloadTimer = null;
    }
  }

  /// Copies finished downloads out of the app-private directory so the files
  /// are visible in the system file manager / other music apps.
  Future<void> _exportFinishedDownloads() async {
    if (!StorageBridge.supported) return;
    var changed = false;
    for (final task in downloads) {
      if (task.status != 'done' || task.path.isEmpty) continue;
      if (_exportedTasks.contains(task.id)) continue;
      _exportedTasks.add(task.id);
      try {
        final location = await StorageBridge.exportAudio(
          path: task.path,
          fileName: p.basename(task.path),
        );
        if (location != null) {
          exportedLocations[task.id] = location;
          changed = true;
        }
      } on StorageException catch (error) {
        exportErrors[task.id] = error.message;
        changed = true;
      } catch (error) {
        exportErrors[task.id] = '$error';
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _pollDownloads() async {
    if (_pollingDownloads) return;
    _pollingDownloads = true;
    try {
      final before = {for (final task in downloads) task.id: task.status};
      await refreshDownloads();
      final finished = downloads.any(
        (task) => task.status == 'done' && before[task.id] != 'done',
      );
      if (finished) await refreshLibrary();
    } catch (_) {
      // A transient local API error must not kill the polling loop.
    } finally {
      _pollingDownloads = false;
    }
  }

  bool isFavorite(Song song) => favoriteKeys.contains(song.key);

  Future<bool> toggleFavorite(Song song) async {
    if (isFavorite(song)) {
      await api.removeSong('favorites', song);
    } else {
      await api.addSongs('favorites', [song]);
    }
    await refreshCollections();
    return isFavorite(song);
  }

  Future<Collection> createCollection(String name) async {
    final collection = await api.createCollection(name);
    await refreshCollections();
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    await api.deleteCollection(id);
    await refreshCollections();
  }

  Future<void> addToCollection(String id, List<Song> songs) async {
    await api.addSongs(id, songs);
    await refreshCollections();
  }

  Future<void> removeFromCollection(String id, Song song) async {
    await api.removeSong(id, song);
    await refreshCollections();
  }

  Future<void> renameCollection(String id, String name) async {
    await api.renameCollection(id, name);
    await refreshCollections();
  }

  Future<void> setDefaultSources(List<String> ids) async {
    final patch = _settingsPatch();
    patch['defaultSearchSources'] = ids;
    settings = await api.updateSettings(patch);
    defaultSources = settings.defaultSearch;
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    final patch = _settingsPatch();
    patch['themeMode'] = mode;
    settings = await api.updateSettings(patch);
    notifyListeners();
  }

  Future<void> setFilenameTemplate(String template) async {
    final patch = _settingsPatch();
    patch['filenameTemplate'] = template;
    settings = await api.updateSettings(patch);
    notifyListeners();
  }

  Map<String, dynamic> _settingsPatch() => {
        'downloadDir': settings.downloadDir,
        'filenameTemplate': settings.filenameTemplate,
        'embedLyrics': true,
        'defaultSearchSources': settings.defaultSearch,
        'preferredQuality': 'best',
        'themeMode': settings.themeMode,
      };

  Future<DownloadEnqueueResult> downloadSongs(List<Song> songs) async {
    final result = await api.download(songs);
    await refreshDownloads();
    return result;
  }

  /// Snackbar text for a download request. Mentions skipped songs so a second
  /// tap on an already downloaded track does not look like a silent failure.
  String describeDownloadEnqueue(DownloadEnqueueResult result) {
    final suffix = StorageBridge.supported ? '，完成后会自动保存到系统音乐' : '';
    if (result.queued == 0) {
      return result.skipped > 0 ? '这些歌曲已经在本地或下载队列中' : '没有可下载的歌曲';
    }
    if (result.skipped > 0) {
      return '已加入下载队列 ${result.queued} 首，${result.skipped} 首已存在$suffix';
    }
    return '已加入下载队列$suffix';
  }

  Future<void> removeDownload(String id) async {
    await api.removeDownload(id);
    await refreshDownloads();
  }

  /// Removes every finished/canceled/failed task with a single refresh instead
  /// of issuing one list request per row.
  Future<int> clearFinishedDownloads() async {
    final ids = downloads
        .where((task) => task.status == 'done' || task.status == 'failed' || task.status == 'canceled')
        .map((task) => task.id)
        .toList();
    if (ids.isEmpty) return 0;
    for (final id in ids) {
      await api.removeDownload(id);
    }
    await refreshDownloads();
    return ids.length;
  }

  Future<void> retryDownload(String id) async {
    await api.retryDownload(id);
    await refreshDownloads();
  }

  Future<void> repairDownloadAssets(String id) async {
    await api.repairDownload(id);
    await refreshDownloads();
  }

  /// Repairs every finished download that still lacks lyrics or cover art.
  /// Returns how many tasks were queued.
  Future<int> repairMissingDownloadAssets() async {
    final queued = await api.repairMissingDownloads();
    await refreshDownloads();
    return queued;
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
  }
}
