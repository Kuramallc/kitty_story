import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kitty_story/firebase_options.dart';
import 'package:kitty_story/src/features/stories/data/story_repository.dart';
import 'package:kitty_story/src/features/stories/domain/story.dart';
import 'package:kitty_story/src/features/voices/data/voice_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Live Phase 3 check against the real backend: clone a voice, generate a
/// kid-safe story with Claude, confirm it persisted, narrate BOTH the generated
/// story and a seeded library story in that voice, and prove each mp3 plays.
/// Exercises generateStory + both library/generated branches of
/// synthesizeNarration's resolveStoryText. Cleans everything up.
///
/// Requires: functions deployed (incl. generateStory), library seeded,
/// ELEVENLABS_API_KEY + ANTHROPIC_API_KEY secrets set.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generate → persist → narrate generated + library in a voice',
      (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final email =
        'kitty.storytest.${DateTime.now().millisecondsSinceEpoch}@example.com';
    final cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'Test123456!');
    final user = cred.user!;

    final functions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);
    final voices = VoiceRepository(
      FirebaseAuth.instance,
      FirebaseFirestore.instance,
      FirebaseStorage.instance,
      functions,
    );
    final stories = StoryRepository(
      FirebaseAuth.instance,
      FirebaseFirestore.instance,
      functions,
    );

    String? voiceId;
    String? generatedId;
    try {
      // 1. Clone a voice from the bundled sample.
      final bytes = await rootBundle.load('assets/test_fixtures/voice_sample.m4a');
      final dir = await getTemporaryDirectory();
      final sample = File('${dir.path}/voice_sample.m4a');
      await sample.writeAsBytes(bytes.buffer.asUint8List());
      voiceId = await voices.createVoiceAndClone(name: 'Test Dad', sample: sample);

      final voiceRef = FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('voices').doc(voiceId);
      final status = await _waitFor(
        () async => (await voiceRef.get()).data()?['status'] as String?,
        (s) => s == 'ready' || s == 'failed',
        timeout: const Duration(minutes: 3),
      );
      expect(status, 'ready');

      // 2. Generate a story with Claude.
      final generated = await stories.generateStory(
        childName: 'Maya',
        theme: 'a sleepy little cloud',
        characters: 'a gentle cloud and the moon',
        ageRange: '4-5 years',
      );
      generatedId = generated.id;
      expect(generated.title.trim(), isNotEmpty);
      expect(generated.text.length, greaterThan(200),
          reason: 'a bedtime story should be a few paragraphs');

      // 3. Confirm it persisted under generatedStories.
      final storyDoc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('generatedStories').doc(generated.id).get();
      expect(storyDoc.exists, isTrue);
      expect(storyDoc.data()!['source'], 'generated');

      // 4. Narrate the GENERATED story in the cloned voice.
      final genUrl = await stories.synthesize(story: generated, voiceId: voiceId);
      final player = AudioPlayer();
      final genDur = await player.setUrl(genUrl);
      expect(genDur, isNotNull);
      expect(genDur!.inSeconds, greaterThan(5),
          reason: 'full story narration should be several seconds');

      // 5. Narrate a seeded LIBRARY story in the same voice.
      const libraryStory = Story(
        id: 'luna-and-the-sleepy-stars',
        source: StorySource.library,
        title: 'Luna and the Sleepy Stars',
        text: '',
      );
      final libUrl = await stories.synthesize(story: libraryStory, voiceId: voiceId);
      final libDur = await player.setUrl(libUrl);
      expect(libDur, isNotNull);
      expect(libDur!.inSeconds, greaterThan(5));
      await player.dispose();
    } finally {
      if (voiceId != null) {
        await voices.deleteVoice(voiceId).catchError((_) {});
      }
      if (generatedId != null) {
        await FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .collection('generatedStories').doc(generatedId)
            .delete().catchError((_) {});
      }
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid).delete().catchError((_) {});
      await user.delete().catchError((_) {});
    }
  });
}

Future<T> _waitFor<T>(
  Future<T> Function() poll,
  bool Function(T) done, {
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  late T value;
  while (DateTime.now().isBefore(end)) {
    value = await poll();
    if (done(value)) return value;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return value;
}
