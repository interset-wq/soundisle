import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api_client.dart';
import 'models.dart';

class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

class PlayerController extends ChangeNotifier {
  PlayerController(this.api) : player = AudioPlayer() {
    _stateSub = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        next(auto: true);
      }
      notifyListeners();
    });
    _errorSub = player.playbackEventStream.listen((_) {}, onError: (Object error, StackTrace stack) {
      errorText = '$error';
      notifyListeners();
    });
  }

  final ApiClient api;
  final AudioPlayer player;

  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<PlaybackEvent> _errorSub;

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
    notifyListeners();
    try {
      final info = await api.play(song);
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
      if (speed != 1.0) {
        await player.setSpeed(speed);
      }
      await player.play();
      unawaited(loadLyrics(song));
    } catch (error) {
      errorText = error is ApiException ? error.message : '$error';
      loading = false;
      notifyListeners();
    } finally {
      loading = false;
      notifyListeners();
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

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> setVolume(double volume) => player.setVolume(volume);

  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    if (index < 0) index = 0;
    if (index + 1 >= queue.length) {
      if (auto) {
        await player.pause();
        await player.seek(Duration.zero);
        return;
      }
      index = 0;
    } else {
      index += 1;
    }
    await playSong(queue[index]);
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
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _stateSub.cancel();
    _errorSub.cancel();
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
