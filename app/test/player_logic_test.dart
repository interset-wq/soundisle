import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundisle/core/models.dart';
import 'package:soundisle/core/player_controller.dart';

Song testSong(String id) => Song(
      id: id,
      name: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      duration: 200,
      source: 'netease',
    );

void main() {
  group('playback snapshot', () {
    test('round-trips queue, position and playback modes', () {
      final snapshot = PlaybackSnapshot(
        songs: [testSong('1'), testSong('2')],
        index: 1,
        position: const Duration(minutes: 1, seconds: 23),
        shuffle: true,
        repeat: PlaybackRepeatMode.one,
        speed: 1.5,
      );
      final restored = decodePlaybackSnapshot(
        jsonEncode(encodePlaybackSnapshot(snapshot)),
      );
      expect(restored, isNotNull);
      expect(restored!.songs.map((e) => e.key), hasLength(2));
      expect(restored.index, 1);
      expect(restored.position, const Duration(minutes: 1, seconds: 23));
      expect(restored.shuffle, isTrue);
      expect(restored.repeat, PlaybackRepeatMode.one);
      expect(restored.speed, 1.5);
    });

    test('ignores corrupt or outdated data', () {
      expect(decodePlaybackSnapshot(null), isNull);
      expect(decodePlaybackSnapshot(''), isNull);
      expect(decodePlaybackSnapshot('not json'), isNull);
      expect(decodePlaybackSnapshot('{"v": 99, "songs": []}'), isNull);
      expect(decodePlaybackSnapshot('{"v": 1, "songs": []}'), isNull);
    });

    test('clamps a stale index into range', () {
      final restored = decodePlaybackSnapshot(jsonEncode({
        'v': playbackSnapshotVersion,
        'songs': [testSong('1').toJson()],
        'index': 9,
        'positionMs': 0,
        'shuffle': false,
        'repeat': 'off',
        'speed': 1.0,
      }));
      expect(restored, isNotNull);
      expect(restored!.index, 0);
    });
  });

  group('playbackEndAction', () {
    test('sleep timer wins over repeat-one', () {
      expect(
        playbackEndAction(
          sleepAfterCurrent: true,
          repeat: PlaybackRepeatMode.one,
          hasNext: true,
        ),
        PlaybackEndAction.pauseAtStart,
      );
    });

    test('repeat-one replays even on the last track', () {
      expect(
        playbackEndAction(
          sleepAfterCurrent: false,
          repeat: PlaybackRepeatMode.one,
          hasNext: false,
        ),
        PlaybackEndAction.replay,
      );
    });

    test('repeat-all advances and wraps on the last track', () {
      expect(
        playbackEndAction(
          sleepAfterCurrent: false,
          repeat: PlaybackRepeatMode.all,
          hasNext: false,
        ),
        PlaybackEndAction.advance,
      );
    });

    test('repeat-off advances while tracks remain', () {
      expect(
        playbackEndAction(
          sleepAfterCurrent: false,
          repeat: PlaybackRepeatMode.off,
          hasNext: true,
        ),
        PlaybackEndAction.advance,
      );
    });

    test('repeat-off pauses at the end of the queue', () {
      expect(
        playbackEndAction(
          sleepAfterCurrent: false,
          repeat: PlaybackRepeatMode.off,
          hasNext: false,
        ),
        PlaybackEndAction.pauseAtStart,
      );
    });
  });

  test('download identity is shared by songs and download tasks', () {
    final song = testSong('42');
    expect(song.downloadKey, 'netease\u000042');
    final task = DownloadTask.fromJson({
      'id': 'dl-1',
      'status': 'done',
      'song': {'id': '42', 'source': 'netease'},
    });
    expect(task.songKey, song.downloadKey);
  });
}
