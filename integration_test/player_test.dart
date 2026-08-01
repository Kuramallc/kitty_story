import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitty_story/src/features/player/audio/audio_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Live check of the bedtime player's core: real playback advances, pause
/// works, and the sleep timer auto-pauses. Drives StoryAudioHandler directly
/// with a local audio file (no clone/synth needed). Building this test also
/// links the audio_service native config, proving it compiles.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play advances, pause stops, sleep timer auto-pauses',
      (tester) async {
    final bytes = await rootBundle.load('assets/test_fixtures/voice_sample.m4a');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/player_fixture.m4a');
    await file.writeAsBytes(bytes.buffer.asUint8List());

    final handler = StoryAudioHandler();
    await handler.loadStory(
      url: Uri.file(file.path).toString(),
      title: 'Test narration',
    );

    // Play → position advances. (Don't await play(): its Future only completes
    // when the clip ends/pauses — so fire it and observe.)
    unawaited(handler.play());
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(handler.playing, isTrue);
    expect(handler.position.inMilliseconds, greaterThan(0),
        reason: 'playback position should advance while playing');

    // Pause → stops.
    await handler.pause();
    expect(handler.playing, isFalse);

    // Sleep timer → auto-pauses.
    unawaited(handler.play());
    expect(handler.playing, isTrue);
    handler.setSleepTimer(const Duration(seconds: 2));
    expect(handler.sleepRemaining.value, isNotNull);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(handler.playing, isFalse, reason: 'sleep timer should pause playback');
    expect(handler.sleepRemaining.value, isNull);

    await handler.stop();
  });
}
