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
import 'package:kitty_story/src/features/community/data/community_repository.dart';
import 'package:kitty_story/src/features/stories/data/story_repository.dart';
import 'package:kitty_story/src/features/voices/data/voice_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Live Phase 4.5 check: generate a story → moderate + propose tags → publish →
/// find it in Explore → like → comment (moderated; an unsafe comment is
/// rejected) → archive → narrate the published story in a cloned voice. Cleans
/// up everything it can client-side and prints the published id for server-side
/// cleanup (publishedStories is Cloud-Function-write-only).
///
/// Requires: community functions deployed, indexes built, secrets set.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generate → publish → explore → like → comment → archive → narrate',
      (tester) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    final email = 'kitty.community.${DateTime.now().millisecondsSinceEpoch}@example.com';
    final cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'Test123456!');
    final user = cred.user!;
    // ignore: avoid_print
    print('E2E_UID=${user.uid}');

    final functions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);
    final voices = VoiceRepository(
        FirebaseAuth.instance, FirebaseFirestore.instance, FirebaseStorage.instance, functions);
    final stories =
        StoryRepository(FirebaseAuth.instance, FirebaseFirestore.instance, functions);
    final community =
        CommunityRepository(FirebaseAuth.instance, FirebaseFirestore.instance, functions);

    String? voiceId;
    String? generatedId;
    String? publishedId;
    try {
      // Clone a voice (for the narration step).
      final bytes = await rootBundle.load('assets/test_fixtures/voice_sample.m4a');
      final dir = await getTemporaryDirectory();
      final sample = File('${dir.path}/voice_sample.m4a');
      await sample.writeAsBytes(bytes.buffer.asUint8List());
      voiceId = await voices.createVoiceAndClone(name: 'Test Gran', sample: sample);
      final voiceRef = FirebaseFirestore.instance
          .collection('users').doc(user.uid).collection('voices').doc(voiceId);
      final vStatus = await _waitFor(
        () async => (await voiceRef.get()).data()?['status'] as String?,
        (s) => s == 'ready' || s == 'failed',
        timeout: const Duration(minutes: 3),
      );
      expect(vStatus, 'ready');

      // Generate a story.
      final generated = await stories.generateStory(
        theme: 'a friendly star that helps a lost bunny home',
        ageRange: '4-5 years',
      );
      generatedId = generated.id;

      // Prepare (moderation + proposed tags).
      final prep = await community.prepareToPublish(generated.id);
      expect(prep.safe, isTrue, reason: 'a generated bedtime story should pass moderation');
      expect(prep.tags.all, isNotEmpty, reason: 'Claude should propose tags');

      // Publish.
      publishedId = await community.publish(generatedStoryId: generated.id, tags: prep.tags);
      // ignore: avoid_print
      print('E2E_PUBLISHED=$publishedId');
      expect(publishedId, isNotEmpty);

      // Appears in Explore (filter by one of its own tags to narrow the page).
      final filterTag = prep.tags.all.first;
      final page = await community.fetchExplore(tags: [filterTag]);
      expect(page.items.any((s) => s.id == publishedId), isTrue,
          reason: 'published story should appear in a tag-filtered Explore query');

      final published = await community.fetchPublished(publishedId);
      expect(published, isNotNull);

      // Like → count goes to 1.
      final like = await community.toggleLike(publishedId);
      expect(like.liked, isTrue);
      expect(like.likeCount, 1);

      // Safe comment posts and shows up.
      await community.addComment(publishedId, 'What a sweet, gentle story. Thank you for sharing!');
      final comments = await _waitFor(
        () async => community.watchComments(publishedId!).first,
        (list) => list.isNotEmpty,
        timeout: const Duration(seconds: 20),
      );
      expect(comments, isNotEmpty);

      // Unsafe comment is rejected by moderation.
      await expectLater(
        community.addComment(publishedId, 'This is stupid garbage and you are an idiot, shut up.'),
        throwsA(isA<FirebaseFunctionsException>()),
        reason: 'an abusive comment should be rejected',
      );

      // Archive → bookmark under the user's account.
      await community.archive(published!);
      final archived = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).collection('archived').doc(publishedId).get();
      expect(archived.exists, isTrue);

      // Narrate the published story in the cloned voice.
      final url = await stories.synthesize(story: published.toStory(), voiceId: voiceId);
      final player = AudioPlayer();
      final duration = await player.setUrl(url);
      expect(duration, isNotNull);
      expect(duration!.inSeconds, greaterThan(5));
      await player.dispose();
    } finally {
      // Client can clean its own subtree; publishedStories is removed out-of-band.
      if (voiceId != null) await voices.deleteVoice(voiceId).catchError((_) {});
      if (generatedId != null) {
        await FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .collection('generatedStories').doc(generatedId).delete().catchError((_) {});
      }
      if (publishedId != null) {
        await FirebaseFirestore.instance
            .collection('users').doc(user.uid)
            .collection('archived').doc(publishedId).delete().catchError((_) {});
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
