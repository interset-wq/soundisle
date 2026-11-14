import 'package:flutter_test/flutter_test.dart';
import 'package:soundisle/core/models.dart';
import 'package:soundisle/core/player_controller.dart';

void main() {
  test('parses LRC timestamps and sorts lines', () {
    final lines = parseLrc('''
[00:12.50]第二句
[00:03.00]第一句
[00:20.123]第三句
''');
    expect(lines.length, 3);
    expect(lines.first.text, '第一句');
    expect(lines.first.time, const Duration(seconds: 3));
    expect(lines[1].time, const Duration(seconds: 12, milliseconds: 500));
    expect(lines.last.time, const Duration(seconds: 20, milliseconds: 123));
  });

  test('song keeps source specific extra data', () {
    final song = Song.fromJson({
      'id': '5257138',
      'name': '屋顶',
      'artist': '周杰伦',
      'source': 'netease',
      'duration': 319,
      'cover': 'https://example.com/cover.jpg',
      'extra': {'song_id': '5257138'},
    });
    expect(song.key, 'netease:5257138');
    expect(song.durationText, '5:19');
    expect(song.extra['song_id'], '5257138');
    expect(song.toJson()['extra'], {'song_id': '5257138'});
  });

  test('search response flattens grouped results', () {
    final response = SearchResponse.fromJson({
      'total': 2,
      'groups': [
        {
          'source': 'netease',
          'name': '网易云音乐',
          'songs': [
            {'id': '1', 'name': 'A', 'artist': 'X', 'source': 'netease'},
            {'id': '2', 'name': 'B', 'artist': 'Y', 'source': 'netease'},
          ],
        },
        {'source': 'qq', 'name': 'QQ 音乐', 'songs': []},
      ],
    });
    expect(response.songs.length, 2);
    expect(response.songs.first.name, 'A');
  });
}
