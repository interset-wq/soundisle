import 'models.dart';

/// How the local library list is organised.
enum LocalGroupMode { none, artist, album }

/// How the local song list is ordered.
enum LocalSortMode { added, title, artist, album }

String localSortLabel(LocalSortMode mode) => switch (mode) {
      LocalSortMode.added => '最近添加',
      LocalSortMode.title => '歌曲名',
      LocalSortMode.artist => '歌手',
      LocalSortMode.album => '专辑',
    };

/// A bucket of local songs sharing the same artist or album.
class SongGroup {
  SongGroup({required this.key, required this.title, this.subtitle = ''});

  /// Unique key; for albums it also includes the artist so two releases with
  /// the same name stay separate.
  final String key;
  final String title;

  /// Secondary line, e.g. the artist for an album group.
  final String subtitle;
  final List<Song> songs = [];
}

/// Filters local songs by a free-text query. Every whitespace-separated term
/// must occur in the title, artist, album or file name, so "jay 晴天" narrows
/// down instead of requiring an exact substring. Matching ignores case.
List<Song> filterLocalSongs(List<Song> songs, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  if (terms.isEmpty) return songs;
  bool matches(Song song) {
    final haystack = [
      song.name,
      song.artist,
      song.album,
      song.extra['fileName'] ?? '',
    ].join('\u0000').toLowerCase();
    return terms.every(haystack.contains);
  }

  return songs.where(matches).toList();
}

/// Sorts local songs for display. Unknown artists and albums sort under their
/// placeholder names so they appear together instead of first. Ties keep the
/// original order (the backend already sorts by artist and title).
List<Song> sortLocalSongs(List<Song> songs, LocalSortMode mode) {
  if (mode == LocalSortMode.added || songs.length < 2) return songs;
  final indexed = [
    for (var i = 0; i < songs.length; i++) (song: songs[i], order: i),
  ];
  String artistOf(Song song) =>
      (song.artist.trim().isEmpty ? '未知歌手' : song.artist.trim())
          .toLowerCase();
  String albumOf(Song song) =>
      (song.album.trim().isEmpty ? '未知专辑' : song.album.trim())
          .toLowerCase();
  int compare(Song a, Song b) {
    switch (mode) {
      case LocalSortMode.title:
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return artistOf(a).compareTo(artistOf(b));
      case LocalSortMode.artist:
        final byArtist = artistOf(a).compareTo(artistOf(b));
        if (byArtist != 0) return byArtist;
        final byAlbum = albumOf(a).compareTo(albumOf(b));
        if (byAlbum != 0) return byAlbum;
        return a.name.compareTo(b.name);
      case LocalSortMode.album:
        final byAlbum = albumOf(a).compareTo(albumOf(b));
        if (byAlbum != 0) return byAlbum;
        final byArtist = artistOf(a).compareTo(artistOf(b));
        if (byArtist != 0) return byArtist;
        return a.name.compareTo(b.name);
      case LocalSortMode.added:
        return 0;
    }
  }

  indexed.sort((a, b) {
    final byValue = compare(a.song, b.song);
    return byValue != 0 ? byValue : a.order.compareTo(b.order);
  });
  return [for (final entry in indexed) entry.song];
}

/// Groups songs for the local library tabs. Order inside a group is preserved
/// (the backend already sorts by artist and title); groups are sorted by name.
List<SongGroup> groupLocalSongs(List<Song> songs, LocalGroupMode mode) {
  if (mode == LocalGroupMode.none || songs.isEmpty) return const [];
  final groups = <String, SongGroup>{};
  for (final song in songs) {
    final artist = song.artist.trim();
    final album = song.album.trim();
    final String key;
    final String title;
    final String subtitle;
    if (mode == LocalGroupMode.artist) {
      title = artist.isEmpty ? '未知歌手' : artist;
      key = title;
      subtitle = '';
    } else {
      title = album.isEmpty ? '未知专辑' : album;
      key = '$title\u0000${artist.isEmpty ? '未知歌手' : artist}';
      subtitle = artist;
    }
    final group = groups.putIfAbsent(
      key,
      () => SongGroup(key: key, title: title, subtitle: subtitle),
    );
    group.songs.add(song);
  }
  final result = groups.values.toList()
    ..sort((a, b) {
      final byTitle = a.title.compareTo(b.title);
      if (byTitle != 0) return byTitle;
      return a.subtitle.compareTo(b.subtitle);
    });
  return result;
}
