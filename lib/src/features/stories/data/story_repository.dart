import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../voices/data/voice_repository.dart' show kFunctionsRegion;
import '../domain/story.dart';

/// Story length the user can ask for, in minutes of narration. Mirrors
/// MIN/MAX/DEFAULT_LENGTH_MINUTES in functions/src/story.ts.
const int kMinStoryMinutes = 1;
const int kMaxStoryMinutes = 5;
const int kDefaultStoryMinutes = 2;

/// How long generation takes for a story of [minutes].
///
/// Measured at the default of two minutes: p50 28s, p90 47s over successful
/// calls. Longer stories are more output tokens and take proportionally
/// longer, on top of a roughly fixed round-trip and think time — hence a
/// constant plus a per-minute term rather than a flat scale. Two minutes still
/// lands on the 45s the bar was paced to before length was selectable.
Duration storyGenerationPace(int minutes) =>
    Duration(seconds: 15 + 15 * minutes);

class StoryRepository {
  StoryRepository(this._auth, this._firestore, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Curated, world-readable library.
  Stream<List<Story>> watchLibrary() {
    return _firestore
        .collection('stories')
        .orderBy('title')
        .snapshots()
        .map((s) => s.docs.map(Story.fromLibraryDoc).toList());
  }

  /// This user's AI-generated stories, newest first.
  /// One-shot read of the user's generated stories.
  ///
  /// Shuffle needs the list *now*; [myStoriesProvider] is autoDispose, so with
  /// nothing listening its `.value` is null and an empty list would be
  /// mistaken for "no stories". Same reasoning as VoiceRepository.fetchVoices.
  Future<List<Story>> fetchGenerated() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    final snapshot = await _firestore
        .collection('users').doc(uid)
        .collection('generatedStories')
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(Story.fromGeneratedDoc).toList();
  }

  Stream<List<Story>> watchGenerated() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('users').doc(uid)
        .collection('generatedStories')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Story.fromGeneratedDoc).toList());
  }

  /// Generates a kid-safe story via Claude and returns it (also persisted
  /// server-side under generatedStories).
  /// Permanently deletes one of the user's generated stories, plus any
  /// narration audio made from it.
  ///
  /// Goes through a Cloud Function rather than deleting the doc directly: the
  /// security rules make narrations function-writable only, so a client-side
  /// delete would leave their records and mp3s orphaned in Storage.
  Future<void> deleteGeneratedStory(String storyId) async {
    await _callable('deleteGeneratedStory', const Duration(minutes: 2))
        .call<Map<String, dynamic>>({'storyId': storyId});
  }

  Future<Story> generateStory({
    String? childName,
    String? theme,
    String? characters,
    String? ageRange,
    int lengthMinutes = kDefaultStoryMinutes,
  }) async {
    final result = await _callable('generateStory', const Duration(minutes: 2))
        .call<Map<String, dynamic>>({
      'childName': childName,
      'theme': theme,
      'characters': characters,
      'ageRange': ageRange,
      'lengthMinutes': lengthMinutes,
    });
    final data = Map<String, dynamic>.from(result.data);
    return Story(
      id: data['storyId'] as String,
      source: StorySource.generated,
      title: data['title'] as String,
      text: data['text'] as String,
      ageRange: ageRange,
    );
  }

  /// Synthesizes (or returns cached) narration of [story] in [voiceId] and
  /// returns the playable mp3 URL.
  Future<String> synthesize({
    required Story story,
    required String voiceId,
  }) async {
    final result =
        await _callable('synthesizeNarration', const Duration(minutes: 9))
            .call<Map<String, dynamic>>({
      'storyId': story.id,
      'storySource': story.source.key,
      'voiceId': voiceId,
    });
    return Map<String, dynamic>.from(result.data)['url'] as String;
  }

  HttpsCallable _callable(String name, Duration timeout) =>
      _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout));
}

final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  return StoryRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseFunctions.instanceFor(region: kFunctionsRegion),
  );
});

final libraryStoriesProvider = StreamProvider.autoDispose<List<Story>>((ref) {
  return ref.watch(storyRepositoryProvider).watchLibrary();
});

final myStoriesProvider = StreamProvider.autoDispose<List<Story>>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(storyRepositoryProvider).watchGenerated();
});
