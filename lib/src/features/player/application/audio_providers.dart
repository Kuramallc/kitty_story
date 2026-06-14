import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';

/// The app-lifetime audio handler. Overridden in `bootstrap()` with the
/// instance returned by `AudioService.init()`. Reading it without that override
/// (e.g. in a widget test that never reaches the player) throws by design.
final audioHandlerProvider = Provider<StoryAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in bootstrap()');
});
