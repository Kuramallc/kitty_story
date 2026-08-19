import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/voice_profile.dart';

/// Must match `REGION` in functions/src/config.ts.
const String kFunctionsRegion = 'us-central1';

/// Version tag stored with each consent acceptance so we can re-prompt if the
/// consent language ever changes.
const String kConsentVersion = '2026-06.1';

class VoiceRepository {
  VoiceRepository(this._auth, this._firestore, this._storage, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _voices(String uid) =>
      _firestore.collection('users').doc(uid).collection('voices');

  /// Live list of this user's voice profiles, newest first.
  Stream<List<VoiceProfile>> watchVoices() {
    return _voices(_uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(VoiceProfile.fromDoc).toList());
  }

  /// One-shot read of this user's voice profiles, newest first.
  ///
  /// Flows that need the list *right now* must use this rather than
  /// [voicesStreamProvider]: that provider is `autoDispose`, so when nothing is
  /// currently listening its `.value` is still null and an empty list would be
  /// mistaken for "no voices".
  Future<List<VoiceProfile>> fetchVoices() async {
    final snapshot =
        await _voices(_uid).orderBy('createdAt', descending: true).get();
    return snapshot.docs.map(VoiceProfile.fromDoc).toList();
  }

  /// Uploads the recorded sample, creates the voice doc (with consent), and
  /// asks the backend to clone it. Returns the new voice doc id.
  ///
  /// The voice doc is created `pending`; the Cloud Function flips it to
  /// `processing` → `ready`/`failed`, which [watchVoices] streams live.
  Future<String> createVoiceAndClone({
    required String name,
    required File sample,
  }) async {
    final uid = _uid;
    final doc = _voices(uid).doc();
    final samplePath = 'users/$uid/voiceSamples/${doc.id}.m4a';

    await _storage.ref(samplePath).putFile(
          sample,
          SettableMetadata(contentType: 'audio/mp4'),
        );
    await doc.set({
      'name': name,
      'status': VoiceStatus.pending.name,
      'samplePath': samplePath,
      'consent': {
        'accepted': true,
        'version': kConsentVersion,
        'at': FieldValue.serverTimestamp(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Cloning takes ~10-60s; the function updates the doc itself, so a
    // transport failure here at worst leaves status visible as pending.
    await _callable('createVoiceProfile', const Duration(minutes: 5))
        .call<Map<String, dynamic>>({'voiceId': doc.id});
    return doc.id;
  }

  /// Synthesizes (or returns the cached) test line for a ready voice and
  /// returns the playable mp3 URL.
  Future<String> synthesizeTestLine(String voiceId) async {
    final result = await _callable('synthesizeNarration', const Duration(minutes: 9))
        .call<Map<String, dynamic>>({
      'storyId': 'sample',
      'storySource': 'test',
      'voiceId': voiceId,
    });
    return Map<String, dynamic>.from(result.data)['url'] as String;
  }

  /// Full delete: ElevenLabs voice, sample, narrations, Firestore doc.
  Future<void> deleteVoice(String voiceId) async {
    await _callable('deleteVoiceProfile', const Duration(minutes: 2))
        .call<Map<String, dynamic>>({'voiceId': voiceId});
  }

  HttpsCallable _callable(String name, Duration timeout) =>
      _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout));
}

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) {
  return VoiceRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    FirebaseFunctions.instanceFor(region: kFunctionsRegion),
  );
});

/// Streams the signed-in user's voices (empty when signed out).
final voicesStreamProvider = StreamProvider.autoDispose<List<VoiceProfile>>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(voiceRepositoryProvider).watchVoices();
});
