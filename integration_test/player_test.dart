import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitty_story/src/features/player/audio/audio_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Live check of the bedtime player's core: real playback advances, pause
/// works, and the sleep timer auto-pauses. Drives StoryAudioHandler directly
/// with a local audio file (no clone/synth needed, so a generated tone works
/// just as well as a real recording). Building this test also links the
/// audio_service native config, proving it compiles.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play advances, pause stops, sleep timer auto-pauses',
      (tester) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/player_fixture.wav');
    await file.writeAsBytes(_sineWaveWav(const Duration(seconds: 8)));

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

/// Builds a mono 16-bit PCM WAV file containing a 440Hz sine tone, purely so
/// StoryAudioHandler has something real to play — no bundled/downloaded
/// fixture needed for a test that never touches cloning or narration.
Uint8List _sineWaveWav(Duration duration) {
  const sampleRate = 44100;
  const frequency = 440.0;
  final sampleCount = sampleRate * duration.inMilliseconds ~/ 1000;
  final data = ByteData(44 + sampleCount * 2);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + sampleCount * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // fmt chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  data.setUint32(40, sampleCount * 2, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final sample = (math.sin(2 * math.pi * frequency * t) * 0.5 * 32767).round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }

  return data.buffer.asUint8List();
}
