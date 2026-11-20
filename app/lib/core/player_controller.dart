import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api_client.dart';
import 'media_session.dart';
import 'permissions.dart';
import 'models.dart';

/// How playback behaves when a track reaches its end.
enum PlaybackRepeatMode {
  /// Stop after the last track in the queue.
  off,

  /// Wrap around to the first track.
  all,

  /// Replay the current track forever.
  one,
}

/// What to do when a track finishes on its own.
enum PlaybackEndAction {
  /// Pause and rewind to the start (queue ended, or sleep timer fired).
  pauseAtStart,

  /// Seek back to the start and keep playing the same track.
  replay,

  /// Move on to the next track (wrapping when repeat-all is on).
  advance,
}

/// Pure decision helper for end-of-track behaviour, kept separate from the
/// audio player so it can be unit tested.
PlaybackEndAction playbackEndAction({
  required bool sleepAfterCurrent,
  required PlaybackRepeatMode repeat,
  required bool hasNext,
}) {
  if (sleepAfterCurrent) return PlaybackEndAction.pauseAtStart;
  if (repeat == PlaybackRepeatMode.one) return PlaybackEndAction.replay;
  if (!hasNext && repeat == PlaybackRepeatMode.off) {
    return PlaybackEndAction.pauseAtStart;
  }
  return PlaybackEndAction.advance;
}

class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

class PlayerController extends ChangeNotifier {
  PlayerController(this.api) : player = AudioPlayer() {
    _stateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleCompleted();
      }
      // The notification's stop action reaches the background audio handler
      // but not this controller. It disposes the platform player, so playback
      // falls back to `idle`; treat that as an external stop.
      if (state.processingState == ProcessingState.idle &&
          current != null &&
          !_stopping) {
        unawaited(handleExternalStop());
      }
      notifyListeners();
    });
    _errorSub = player.playbackEventStream.listen(
      (_) => _ensureSessionWatch(),
      onError: (Object error, StackTrace stack) {
        errorText = '$error';
        notifyListeners();
      },
    );
    unawaited(_configureAudioSession());
  }

  final ApiClient api;
  final AudioPlayer player;

  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<PlaybackEvent> _errorSub;
  StreamSubscription<void>? _noisySub;

  List<Song> queue = [];
  int index = -1;
  Song? current;
  PlayInfo? playInfo;
  bool loading = false;
  String? errorText;
  String rawLyric = '';
  List<LyricLine> lyrics = [];
  bool lyricsLoading = false;
  bool shuffle = false;

  /// End-of-track behaviour. Not persisted; every session starts at
  /// [PlaybackRepeatMode.off] like the stock music app.
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;

  /// When true, playback pauses as soon as the current track finishes. Used by
  /// the sleep timer's "after this song" option.
  bool sleepAfterCurrent = false;

  /// Notified whenever a track starts playing, so the UI can keep a
  /// "recently played" list without the controller knowing about storage.
  void Function(Song song)? onSongStarted;

  /// Playback speed, 1.0 = normal. Applied when a new track starts too.
  double speed = 1.0;

  /// When set, playback pauses automatically at that moment.
  DateTime? sleepAt;
  Timer? _sleepTimer;
  Timer? _sleepTicker;

  Duration? get sleepRemaining {
    final at = sleepAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> setSpeed(double value) async {
    speed = value.clamp(0.5, 3.0);
    try {
      await player.setSpeed(speed);
    } catch (_) {}
    notifyListeners();
  }

  /// Starts a sleep timer, or clears it when [duration] is null.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    // A countdown and "stop after this song" are mutually exclusive.
    sleepAfterCurrent = false;
    if (duration == null) {
      sleepAt = null;
      notifyListeners();
      return;
    }
    sleepAt = DateTime.now().add(duration);
    // Keep the countdown label fresh in the player page.
    _sleepTicker = Timer.periodic(const Duration(seconds: 30), (_) => notifyListeners());
    _sleepTimer = Timer(duration, () async {
      _sleepTimer = null;
      _sleepTicker?.cancel();
      _sleepTicker = null;
      sleepAt = null;
      try {
        await player.pause();
      } catch (_) {}
      notifyListeners();
    });
    notifyListeners();
  }

  /// Cycles off → list repeat → single repeat → off.
  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    notifyListeners();
  }

  /// Pauses when the current track ends instead of advancing. Cancels any
  /// countdown timer so only one sleep rule is active.
  void setSleepAfterCurrent(bool value) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    sleepAt = null;
    sleepAfterCurrent = value;
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle && queue.length > 1) {
      final currentSong = current;
      final rest = queue.where((e) => e.key != currentSong?.key).toList()..shuffle();
      queue = [?currentSong, ...rest];
      index = 0;
    }
    notifyListeners();
  }

  bool get hasSong => current != null;
  bool get playing => player.playing;
  bool get preview => playInfo?.preview ?? false;
  Duration get position => player.position;
  Duration? get duration => player.duration;

  Duration get effectiveDuration {
    final value = player.duration;
    if (value != null && value > const Duration(seconds: 1)) return value;
    return Duration(seconds: current?.duration ?? 0);
  }

  Future<void> playSong(Song song, {List<Song>? queue, int startIndex = -1}) async {
    final oldQueue = this.queue;
    if (queue != null) {
      this.queue = List<Song>.from(queue);
      index = startIndex >= 0 ? startIndex : this.queue.indexWhere((e) => e.key == song.key);
      if (index < 0) {
        this.queue.insert(0, song);
        index = 0;
      }
    } else if (!oldQueue.any((e) => e.key == song.key)) {
      this.queue = [song];
      index = 0;
    } else {
      this.queue = oldQueue;
      index = oldQueue.indexWhere((e) => e.key == song.key);
    }
    current = song;
    loading = true;
    errorText = null;
    onSongStarted?.call(song);
    notifyListeners();
    // Ask for the notification permission in the context of an actual play
    // action; a request at cold start is easy to miss (and some ROMs deny it).
    unawaited(AppPermissions.requestNotificationPermission());
    try {
      final info = await api.play(song);
      // A second tap may have selected another song while this request was in
      // flight; never let the older response replace the newer track.
      if (current?.key != song.key) return;
      playInfo = info;
      final cover = api.coverUrl(song.cover, source: song.source);
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(info.url),
        tag: MediaItem(
          id: song.key,
          album: song.album.isEmpty ? '音乐' : song.album,
          title: song.name,
          artist: song.artist,
          artUri: cover.isEmpty ? null : Uri.parse(cover),
        ),
      ));
      if (current?.key != song.key) return;
      if (speed != 1.0) {
        await player.setSpeed(speed);
      }
      await player.play();
      _ensureSessionWatch();
      unawaited(loadLyrics(song));
    } catch (error) {
      if (current?.key != song.key) return;
      errorText = error is ApiException ? error.message : '$error';
    } finally {
      if (current?.key == song.key) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadLyrics(Song song) async {
    lyricsLoading = true;
    rawLyric = '';
    lyrics = [];
    notifyListeners();
    try {
      final raw = await api.lyric(song);
      if (current?.key != song.key) return;
      rawLyric = raw;
      lyrics = parseLrc(raw);
    } catch (_) {
      lyrics = [];
    } finally {
      if (current?.key == song.key) {
        lyricsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggle() async {
    if (!hasSong) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
  }

  Future<void> pause() => player.pause();

  bool _stopping = false;
  bool _handlingCompletion = false;
  bool _disposed = false;
  bool _sessionWatched = false;
  bool _watchPending = false;

  /// The foreground service is created asynchronously after playback starts,
  /// so keep retrying until the shell can attach its stop listener.
  void _ensureSessionWatch() {
    if (_sessionWatched || _watchPending) return;
    _watchPending = true;
    MediaSession.watch().then((ok) {
      _watchPending = false;
      if (ok) _sessionWatched = true;
    }, onError: (_) {
      _watchPending = false;
    });
  }

  /// Ends the session and removes the ongoing media notification.
  Future<void> stop() async {
    _stopping = true;
    try {
      try {
        await player.stop();
      } catch (_) {}
      // audio_service cannot destroy its bound foreground service, so the
      // media card would linger; the shell removes it explicitly.
      await MediaSession.stop();
      _resetSession();
    } finally {
      _stopping = false;
    }
  }

  /// Handles a stop triggered from the notification, which never reaches the
  /// Dart isolate on its own.
  Future<void> handleExternalStop() async {
    if (_stopping) return;
    _stopping = true;
    try {
      try {
        await player.stop();
      } catch (_) {}
      await MediaSession.stop();
      _resetSession();
    } finally {
      _stopping = false;
    }
  }

  void _resetSession() {
    _sessionWatched = false;
    current = null;
    playInfo = null;
    loading = false;
    errorText = null;
    rawLyric = '';
    lyrics = [];
    queue = [];
    index = -1;
    notifyListeners();
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> setVolume(double volume) => player.setVolume(volume);

  /// Called when a track reaches its natural end (not when the user taps
  /// "next"). Applies the sleep timer and repeat mode before auto-advancing.
  Future<void> _handleCompleted() async {
    if (_stopping || _handlingCompletion || queue.isEmpty) return;
    _handlingCompletion = true;
    try {
      final action = playbackEndAction(
        sleepAfterCurrent: sleepAfterCurrent,
        repeat: repeatMode,
        hasNext: index + 1 < queue.length,
      );
      switch (action) {
        case PlaybackEndAction.pauseAtStart:
          if (sleepAfterCurrent) {
            sleepAfterCurrent = false;
            notifyListeners();
          }
          await player.pause();
          await player.seek(Duration.zero);
        case PlaybackEndAction.replay:
          await player.seek(Duration.zero);
          await player.play();
        case PlaybackEndAction.advance:
          await next();
      }
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    if (index < 0) index = 0;
    if (index + 1 >= queue.length) {
      // Manual "next" always wraps so the control never feels dead; automatic
      // end-of-queue handling happens in [_handleCompleted].
      index = 0;
    } else {
      index += 1;
    }
    await playSong(queue[index]);
  }

  /// Pauses when headphones are unplugged or a Bluetooth headset disconnects,
  /// matching the stock Android music app. just_audio handles audio focus and
  /// interruptions, but not the "becoming noisy" broadcast.
  Future<void> _configureAudioSession() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      if (_disposed) return;
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (player.playing) unawaited(player.pause());
      });
    } catch (_) {
      // Audio session support varies by platform; playback still works.
    }
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (player.position > const Duration(seconds: 4)) {
      await player.seek(Duration.zero);
      return;
    }
    index = index <= 0 ? queue.length - 1 : index - 1;
    await playSong(queue[index]);
  }

  void playNext(Song song) {
    if (queue.isEmpty) {
      queue = [song];
      return;
    }
    queue.insert(index < 0 ? 0 : index + 1, song);
    notifyListeners();
  }

  void addToQueue(Song song) {
    queue.add(song);
    notifyListeners();
  }

  void removeFromQueue(int at) {
    if (at < 0 || at >= queue.length) return;
    queue.removeAt(at);
    if (at < index) index -= 1;
    if (at == index && queue.isNotEmpty) {
      index = index.clamp(0, queue.length - 1);
      playSong(queue[index]);
    }
    notifyListeners();
  }

  /// Moves an entry inside the queue, keeping the playing index correct.
  void moveQueueItem(int from, int to) {
    if (from == to) return;
    if (from < 0 || from >= queue.length) return;
    if (to < 0 || to >= queue.length) return;
    final song = queue.removeAt(from);
    queue.insert(to, song);
    if (index == from) {
      index = to;
    } else if (from < index && to >= index) {
      index -= 1;
    } else if (from > index && to <= index) {
      index += 1;
    }
    notifyListeners();
  }

  int get currentLyricIndex {
    if (lyrics.isEmpty) return -1;
    final pos = position;
    var result = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].time <= pos) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _stateSub.cancel();
    _errorSub.cancel();
    _noisySub?.cancel();
    player.dispose();
    super.dispose();
  }
}

List<LyricLine> parseLrc(String raw) {
  final lines = <LyricLine>[];
  if (raw.trim().isEmpty) return lines;
  final regex = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final line in raw.split('\n')) {
    final matches = regex.allMatches(line);
    if (matches.isEmpty) continue;
    final text = line.replaceAll(regex, '').trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fractionRaw = match.group(3) ?? '0';
      final fraction = int.tryParse(fractionRaw) ?? 0;
      final ms = fractionRaw.length == 2 ? fraction * 10 : (fractionRaw.length == 1 ? fraction * 100 : fraction);
      lines.add(LyricLine(
        Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
        text,
      ));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  final deduped = <LyricLine>[];
  for (final line in lines) {
    if (deduped.isNotEmpty && deduped.last.time == line.time && deduped.last.text == line.text) {
      continue;
    }
    deduped.add(line);
  }
  return deduped;
}
