import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Wraps a just_audio player and exposes it to the OS via audio_service so
/// narration keeps playing with the screen off and shows lock-screen controls.
class StoryAudioHandler extends BaseAudioHandler {
  StoryAudioHandler() {
    // listen (not pipe): pipe() puts playbackState into addStream mode, which
    // makes BaseAudioHandler.stop()'s direct add() throw "cannot add while
    // items are being added from addStream".
    _player.playbackEventStream.listen(
      (event) => playbackState.add(_transformEvent(event)),
    );
  }

  final AudioPlayer _player = AudioPlayer();

  /// Remaining sleep-timer time, or null when off. Lives here (app-lifetime) so
  /// it keeps running when the user leaves the player screen.
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier<Duration?>(null);
  Timer? _sleepTimer;
  String? _currentUrl;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  bool get playing => _player.playing;
  Duration get position => _player.position;

  /// Loads [url] for playback and shows [title] on the lock screen. Skips the
  /// reload if the same url is already loaded.
  Future<void> loadStory({
    required String url,
    required String title,
    String? subtitle,
  }) async {
    mediaItem.add(MediaItem(id: url, title: title, album: subtitle ?? 'Kitty Story'));
    if (_currentUrl != url) {
      _currentUrl = url;
      await _player.setUrl(url);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() =>
      _player.seek(_player.position + const Duration(seconds: 15));

  @override
  Future<void> rewind() {
    final target = _player.position - const Duration(seconds: 15);
    return _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> stop() async {
    setSleepTimer(null);
    await _player.stop();
    await super.stop();
  }

  /// Auto-pause after [total]; pass null to cancel.
  void setSleepTimer(Duration? total) {
    _sleepTimer?.cancel();
    if (total == null) {
      sleepRemaining.value = null;
      return;
    }
    var remaining = total;
    sleepRemaining.value = remaining;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        timer.cancel();
        sleepRemaining.value = null;
        pause();
      } else {
        sleepRemaining.value = remaining;
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
