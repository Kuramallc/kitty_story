import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kitty_story/firebase_options.dart';
import 'package:kitty_story/src/features/voices/data/voice_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Live end-to-end check of the Phase 2 voice pipeline against the real
/// backend: upload a (synthetic) voice sample → createVoiceProfile clones it
/// with ElevenLabs → voice doc turns "ready" → synthesizeNarration returns a
/// playable mp3 in that voice → just_audio can load it → full cleanup.
///
/// Bypasses the recording UI on purpose (a simulator can't speak); the
/// repository call is exactly what the record screen invokes.
///
/// Requires: functions deployed, Storage set up, ELEVENLABS_API_KEY secret
/// with a plan that includes Instant Voice Cloning.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('upload → clone → ready → narrate → play → delete',
      (tester) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Required once App Check enforcement is on; harmless while it's off.
    await FirebaseAppCheck.instance.activate(
      providerApple: const AppleDebugProvider(),
      providerAndroid: const AndroidDebugProvider(),
    );

    // Fresh throwaway account.
    final email =
        'kitty.voicetest.${DateTime.now().millisecondsSinceEpoch}@example.com';
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: 'Test123456!');
    final user = credential.user!;

    final repository = VoiceRepository(
      FirebaseAuth.instance,
      FirebaseFirestore.instance,
      FirebaseStorage.instance,
      FirebaseFunctions.instanceFor(region: kFunctionsRegion),
    );

    String? voiceId;
    try {
      // Materialize the bundled synthetic sample as a file.
      final bytes =
          await rootBundle.load('assets/test_fixtures/voice_sample.m4a');
      final dir = await getTemporaryDirectory();
      final sample = File('${dir.path}/voice_sample.m4a');
      await sample.writeAsBytes(bytes.buffer.asUint8List());

      // Upload + clone (the function updates the doc as it progresses).
      voiceId = await repository.createVoiceAndClone(
        name: 'Test Mom',
        sample: sample,
      );

      // The callable returns after cloning, but assert the doc state too.
      final voiceRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('voices')
          .doc(voiceId);
      final status = await _waitFor(
        () async => (await voiceRef.get()).data()?['status'] as String?,
        (s) => s == 'ready' || s == 'failed',
        timeout: const Duration(minutes: 3),
      );
      expect(status, 'ready',
          reason: 'voice doc error: ${(await voiceRef.get()).data()?['error']}');

      // Narrate the test line in the cloned voice and prove it's playable.
      final url = await repository.synthesizeTestLine(voiceId);
      expect(url, startsWith('https://'));
      final player = AudioPlayer();
      final duration = await player.setUrl(url);
      expect(duration, isNotNull);
      expect(duration!.inMilliseconds, greaterThan(1000),
          reason: 'narration should be at least a second long');
      await player.dispose();

      // Cached replay: same (story, voice) must return the same audio path
      // without re-synthesis (billing guard).
      final cachedUrl = await repository.synthesizeTestLine(voiceId);
      expect(cachedUrl, url);
    } finally {
      // Cleanup: voice (EL voice + sample + narrations + doc), then account.
      // Sweep the whole collection (not just voiceId) so a failure inside
      // createVoiceAndClone — before it returns the id — leaves no orphans.
      final leftovers = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('voices')
          .get()
          .catchError((_) => throw StateError('unreachable'));
      for (final doc in leftovers.docs) {
        await repository.deleteVoice(doc.id).catchError((_) {});
      }
      if (voiceId != null && !leftovers.docs.any((d) => d.id == voiceId)) {
        await repository.deleteVoice(voiceId).catchError((_) {});
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete()
          .catchError((_) {});
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
