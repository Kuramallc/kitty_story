import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';

/// The app-lifetime audio handler. Overridden in `bootstrap()` with the
/// instance returned by `AudioService.init()`. Reading it without that override
/// (e.g. in a widget test that never reaches the player) throws by design.
final audioHandlerProvider = Provider<StoryAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in bootstrap()');
});

/// The same handler, or null when `AudioService.init()` failed in bootstrap.
///
/// [audioHandlerProvider] throws when unoverridden, which is right for the
/// player screen — it cannot work without one. The mini-player is different:
/// it renders on every screen, so it has to degrade to nothing rather than
/// take the whole app down on a device where audio failed to start.
final audioHandlerOrNullProvider = Provider<StoryAudioHandler?>((ref) => null);
