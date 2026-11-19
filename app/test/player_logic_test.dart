import 'package:flutter_test/flutter_test.dart';
import 'package:soundisle/core/player_controller.dart';

void main() {
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
}
