import 'models.dart';

/// How the local library list is organised.
enum LocalGroupMode { none, artist, album }

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
