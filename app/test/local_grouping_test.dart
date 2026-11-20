import 'package:flutter_test/flutter_test.dart';
import 'package:soundisle/core/local_grouping.dart';
import 'package:soundisle/core/models.dart';

Song localSong({
  required String id,
  required String name,
  String artist = '',
  String album = '',
}) {
  return Song(
    id: id,
    name: name,
    artist: artist,
    album: album,
    source: 'local',
  );
}

void main() {
  filterTests();
  sortTests();

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
    expect(
      groupLocalSongs([localSong(id: '1', name: 'A')], LocalGroupMode.none),
      isEmpty,
    );
    expect(groupLocalSongs(const [], LocalGroupMode.artist), isEmpty);
  });
}

final sampleSongs = [
  Song(
    id: '1',
    name: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    source: 'local',
    extra: const {'fileName': '周杰伦 - 晴天.mp3'},
  ),
  Song(
    id: '2',
    name: 'Lemon',
    artist: '米津玄師',
    album: 'STRAY SHEEP',
    source: 'local',
  ),
  Song(id: '3', name: '夜曲', artist: '周杰伦', album: '十一月的萧邦', source: 'local'),
];

void sortTests() {
  final songs = [
    localSong(id: '1', name: 'b', artist: 'Zed', album: 'Two'),
    localSong(id: '2', name: 'A', artist: 'amy', album: 'One'),
    localSong(id: '3', name: 'c', artist: 'Zed', album: 'One'),
    localSong(id: '4', name: 'd'),
  ];

  test('added mode keeps the original order', () {
    expect(sortLocalSongs(songs, LocalSortMode.added), same(songs));
  });

  test('title mode ignores case', () {
    expect(
      sortLocalSongs(songs, LocalSortMode.title).map((e) => e.name).toList(),
      ['A', 'b', 'c', 'd'],
    );
  });

  test('artist mode keeps albums and titles together per artist', () {
    final sorted = sortLocalSongs(songs, LocalSortMode.artist);
    expect(sorted.map((e) => e.artist).toList(), ['amy', 'Zed', 'Zed', '']);
    expect(sorted[1].name, 'c');
    expect(sorted[2].name, 'b');
  });

  test('album mode puts unknown albums last and is stable inside a tie', () {
    final sorted = sortLocalSongs(songs, LocalSortMode.album);
    expect(sorted.map((e) => e.album).toList(), ['One', 'One', 'Two', '']);
    expect(sorted[0].name, 'A');
    expect(sorted[1].name, 'c');
  });

  test('short lists are returned untouched', () {
    final single = [localSong(id: '1', name: 'A')];
    expect(sortLocalSongs(single, LocalSortMode.artist), same(single));
  });
}

void filterTests() {
  test('empty query returns the original list', () {
    expect(filterLocalSongs(sampleSongs, '   '), same(sampleSongs));
  });

  test('matches title, artist and album case-insensitively', () {
    expect(filterLocalSongs(sampleSongs, '晴天').map((e) => e.id), ['1']);
    expect(filterLocalSongs(sampleSongs, '周杰伦').map((e) => e.id), ['1', '3']);
    expect(filterLocalSongs(sampleSongs, 'stray').map((e) => e.id), ['2']);
  });

  test('every whitespace-separated term must match', () {
    expect(filterLocalSongs(sampleSongs, '周杰伦 夜').map((e) => e.id), ['3']);
    expect(filterLocalSongs(sampleSongs, '周杰伦 lemon'), isEmpty);
  });

  test('falls back to the exported file name', () {
    expect(filterLocalSongs(sampleSongs, '周杰伦 - 晴天.mp3').map((e) => e.id), [
      '1',
    ]);
  });
}
