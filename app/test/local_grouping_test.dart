import 'package:flutter_test/flutter_test.dart';
import 'package:soundisle/core/local_grouping.dart';
import 'package:soundisle/core/models.dart';

Song localSong({
  required String id,
  required String name,
  String artist = '',
  String album = '',
}) {
  return Song(id: id, name: name, artist: artist, album: album, source: 'local');
}

void main() {
  test('artist mode merges songs and sorts groups by name', () {
    final groups = groupLocalSongs([
      localSong(id: '1', name: 'A', artist: '周杰伦'),
      localSong(id: '2', name: 'B', artist: '陈奕迅'),
      localSong(id: '3', name: 'C', artist: '周杰伦'),
      localSong(id: '4', name: 'D'),
    ], LocalGroupMode.artist);

    expect(groups.map((e) => e.title).toList(), ['周杰伦', '未知歌手', '陈奕迅']);
    expect(groups.first.songs.map((e) => e.name).toList(), ['A', 'C']);
    expect(groups[1].songs.single.name, 'D');
  });

  test('album mode separates the same album title by artist', () {
    final groups = groupLocalSongs([
      localSong(id: '1', name: 'A', artist: 'X', album: 'Live'),
      localSong(id: '2', name: 'B', artist: 'Y', album: 'Live'),
      localSong(id: '3', name: 'C', artist: 'X', album: 'Live'),
    ], LocalGroupMode.album);

    expect(groups.length, 2);
    expect(groups.every((group) => group.title == 'Live'), isTrue);
    expect(groups.map((group) => group.songs.length).toList(), [2, 1]);
    expect(groups.first.subtitle, 'X');
  });

  test('unknown albums stay separate per artist', () {
    final groups = groupLocalSongs([
      localSong(id: '1', name: 'A', artist: 'X'),
      localSong(id: '2', name: 'B', artist: 'Y'),
    ], LocalGroupMode.album);

    expect(groups.length, 2);
    expect(groups.every((group) => group.title == '未知专辑'), isTrue);
  });

  test('flat mode returns no groups', () {
    expect(groupLocalSongs([localSong(id: '1', name: 'A')], LocalGroupMode.none), isEmpty);
    expect(groupLocalSongs(const [], LocalGroupMode.artist), isEmpty);
  });
}
