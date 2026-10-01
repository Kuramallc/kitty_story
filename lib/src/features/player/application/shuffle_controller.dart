import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stories/domain/story.dart';
import '../audio/audio_handler.dart';
import 'audio_providers.dart';

/// Synthesizes (or returns a cached) narration URL for one story.
typedef NarrateStory = Future<String> Function(Story story, String voiceId);

/// Plays the user's own stories end to end, in random order, until they stop.
///
/// Lives for the life of the app rather than inside a screen: the whole point
/// is that it keeps going after the player is dismissed, with the mini-player
/// the only thing still on screen.
///
/// Replays are free — a narration already synthesized for this (story, voice)
/// is served from cache and costs no quota — so shuffle runs indefinitely over
/// a library that has been heard before. A story that has *never* been
/// narrated has to be synthesized first, which takes 15-30s and counts against
/// the free plan; that is the same cost as playing it directly, just reached
/// without asking.
class ShuffleController {
  ShuffleController(this._handler);

  final StoryAudioHandler _handler;
  final Random _random = Random();

  /// True while shuffle owns playback. The home screen watches this so the
  /// button can show as active.
  final ValueNotifier<bool> isOn = ValueNotifier<bool>(false);

  StreamSubscription<PlaybackState>? _sub;
  List<Story> _pool = const [];
  String _voiceId = '';
  NarrateStory? _narrate;
  void Function(Object error)? _onError;
  Story? _current;

  /// Guards the window where we are loading the next story. Transitions during
  /// a load must not be read as the user having stopped.
  bool _advancing = false;

  /// Starts shuffling [pool]. Returns once the first story is playing, so the
  /// caller can navigate to the player with something already loaded.
  Future<void> start({
    required List<Story> pool,
    required String voiceId,
    required NarrateStory narrate,
    void Function(Object error)? onError,
  }) async {
    _pool = pool;
    _voiceId = voiceId;
    _narrate = narrate;
    _onError = onError;
    _current = null;
    isOn.value = true;
    _sub ??= _handler.playbackState.listen(_onPlaybackState);
    await _advance();
  }

  Future<void> stop() async {
    isOn.value = false;
    await _sub?.cancel();
    _sub = null;
    _pool = const [];
    _current = null;
  }

  void _onPlaybackState(PlaybackState state) {
    if (!isOn.value || _advancing) return;
    switch (state.processingState) {
      case AudioProcessingState.completed:
        unawaited(_advance());
      case AudioProcessingState.idle:
        // Stop means stop: the user hit the square, or the handler was torn
        // down. Either way shuffle is over.
        unawaited(stop());
      default:
        break;
    }
  }

  /// The currently playing story, or null when shuffle is off.
  Story? get current => _current;

  Future<void> _advance() async {
    if (_advancing) return;
    _advancing = true;
    try {
      final next = _pickNext();
      if (next == null) {
        await stop();
        return;
      }
      final url = await _narrate!(next, _voiceId);
      _current = next;
      await _handler.loadStory(url: url, title: next.title);
      // Never await play(): just_audio only completes that future when the
      // clip ends, so awaiting it would hang here until the story finishes.
      unawaited(_handler.play());
    } catch (error) {
      await stop();
      _onError?.call(error);
    } finally {
      _advancing = false;
    }
  }

  /// A random story, never the one that just played — hearing the same story
  /// twice in a row reads as broken rather than random.
  Story? _pickNext() {
    if (_pool.isEmpty) return null;
    if (_pool.length == 1) return _pool.first;
    final others = _pool.where((s) => s.id != _current?.id).toList();
    return others[_random.nextInt(others.length)];
  }

  void dispose() {
    _sub?.cancel();
    isOn.dispose();
  }
}

/// Null when audio failed to start in bootstrap — the same degradation as
/// [audioHandlerOrNullProvider], so a device without audio shows a disabled
/// button rather than crashing.
final shuffleControllerProvider = Provider<ShuffleController?>((ref) {
  final handler = ref.watch(audioHandlerOrNullProvider);
  if (handler == null) return null;
  final controller = ShuffleController(handler);
  ref.onDispose(controller.dispose);
  return controller;
});
