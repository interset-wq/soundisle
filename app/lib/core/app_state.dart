import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';

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
    _downloadTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _pollDownloads());
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

  Future<void> refreshDownloads() async {
    downloads = await api.downloads();
    notifyListeners();
  }

  Future<void> _pollDownloads() async {
    try {
      final before = {for (final task in downloads) task.id: task.status};
      await refreshDownloads();
      final finished = downloads.any((task) => task.status == 'done' && before[task.id] != 'done');
      if (finished) await refreshLibrary();
    } catch (_) {}
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

  Future<void> downloadSongs(List<Song> songs) async {
    await api.download(songs);
    await refreshDownloads();
  }

  Future<void> removeDownload(String id) async {
    await api.removeDownload(id);
    await refreshDownloads();
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
  }
}
