import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundisle/core/api_client.dart';
import 'package:soundisle/core/app_state.dart';
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

  test('download polling is active only while a task runs', () {
    final app = AppState(
      ApiClient(baseUrl: 'http://127.0.0.1:1', token: 'test'),
    );
    app.downloads = [
      const DownloadTask(id: '1', name: 'done', status: 'done'),
      const DownloadTask(id: '2', name: 'failed', status: 'failed'),
    ];
    expect(app.hasActiveDownloads, isFalse);
    app.downloads = [
      const DownloadTask(id: '3', name: 'waiting', status: 'waiting'),
    ];
    expect(app.hasActiveDownloads, isTrue);
    app.downloads = [
      const DownloadTask(
        id: '4',
        name: 'repairing',
        status: 'done',
        repairing: true,
      ),
    ];
    expect(app.hasActiveDownloads, isTrue);
  });

  test('download message explains skipped songs', () {
    final app = AppState(
      ApiClient(baseUrl: 'http://127.0.0.1:1', token: 'test'),
    );
    final mixed = app.describeDownloadEnqueue(
      const DownloadEnqueueResult(queued: 2, skipped: 1),
    );
    expect(mixed, contains('2 首'));
    expect(mixed, contains('1 首已存在'));
    expect(
      app.describeDownloadEnqueue(
        const DownloadEnqueueResult(queued: 0, skipped: 3),
      ),
      contains('已经在本地'),
    );
  });

  test('recently played keeps newest first and de-duplicates', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final app = AppState(ApiClient(baseUrl: 'http://127.0.0.1:1', token: 'test'));
    const a = Song(id: '1', name: 'A', artist: 'X', source: 'netease');
    const b = Song(id: '2', name: 'B', artist: 'Y', source: 'qq');

    await app.recordPlayed(a);
    await app.recordPlayed(b);
    await app.recordPlayed(a);

    expect(app.recentSongs.map((e) => e.name).toList(), ['A', 'B']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('library.recent_songs')?.length, 2);
  });
}
