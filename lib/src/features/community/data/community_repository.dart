import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../voices/data/voice_repository.dart' show kFunctionsRegion;
import '../domain/published_story.dart';

/// One page of Explore results plus the cursor for "load more".
class ExplorePage {
  const ExplorePage({required this.items, required this.lastDoc, required this.hasMore});

  final List<PublishedStory> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;
}

class CommunityRepository {
  CommunityRepository(this._auth, this._firestore, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  static const int pageSize = 20;

  CollectionReference<Map<String, dynamic>> get _published =>
      _firestore.collection('publishedStories');

  /// Explore feed: top by likes, optionally filtered to stories carrying any of
  /// [tags] (max 10). Pass [startAfter] to page.
  Future<ExplorePage> fetchExplore({
    List<String> tags = const [],
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query =
        _published.where('status', isEqualTo: 'published');
    if (tags.isNotEmpty) {
      query = query.where('allTags', arrayContainsAny: tags.take(10).toList());
    }
    query = query
        .orderBy('likeCount', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (startAfter != null) query = query.startAfterDocument(startAfter);

    final snap = await query.get();
    return ExplorePage(
      items: snap.docs.map(PublishedStory.fromDoc).toList(),
      lastDoc: snap.docs.isEmpty ? startAfter : snap.docs.last,
      hasMore: snap.docs.length == pageSize,
    );
  }

  Future<PublishedStory?> fetchPublished(String id) async {
    final doc = await _published.doc(id).get();
    return doc.exists ? PublishedStory.fromDoc(doc) : null;
  }

  /// Moderates a generated story + proposes tags for the publish editor.
  Future<({bool safe, String reason, StoryTags tags})> prepareToPublish(
      String generatedStoryId) async {
    final res = await _call('prepareStoryForPublish')
        .call<Map<String, dynamic>>({'generatedStoryId': generatedStoryId});
    final d = Map<String, dynamic>.from(res.data);
    return (
      safe: d['safe'] as bool,
      reason: (d['reason'] as String?) ?? '',
      tags: StoryTags.fromMap(Map<String, dynamic>.from(d['tags'] as Map)),
    );
  }

  Future<String> publish({
    required String generatedStoryId,
    required StoryTags tags,
  }) async {
    final res = await _call('publishStory').call<Map<String, dynamic>>({
      'generatedStoryId': generatedStoryId,
      'tags': tags.toMap(),
    });
    return Map<String, dynamic>.from(res.data)['publishedStoryId'] as String;
  }

  Future<({bool liked, int likeCount})> toggleLike(String publishedStoryId) async {
    final res = await _call('toggleLike')
        .call<Map<String, dynamic>>({'publishedStoryId': publishedStoryId});
    final d = Map<String, dynamic>.from(res.data);
    return (liked: d['liked'] as bool, likeCount: (d['likeCount'] as num).toInt());
  }

  Stream<bool> watchLiked(String publishedStoryId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _published
        .doc(publishedStoryId).collection('likes').doc(uid)
        .snapshots()
        .map((s) => s.exists);
  }

  Stream<List<StoryComment>> watchComments(String publishedStoryId) {
    return _published
        .doc(publishedStoryId).collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(StoryComment.fromDoc).toList());
  }

  Future<void> addComment(String publishedStoryId, String text) async {
    await _call('addComment')
        .call<Map<String, dynamic>>({'publishedStoryId': publishedStoryId, 'text': text});
  }

  Future<void> report(String publishedStoryId, String reason) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _published.doc(publishedStoryId).collection('reports').add({
      'reporterUid': uid,
      'reason': reason,
      'at': FieldValue.serverTimestamp(),
    });
  }

  // --- Archive (client-managed bookmarks under users/{uid}/archived) ---

  DocumentReference<Map<String, dynamic>>? _archiveDoc(String publishedStoryId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore
        .collection('users').doc(uid)
        .collection('archived').doc(publishedStoryId);
  }

  Future<void> archive(PublishedStory story) async {
    final ref = _archiveDoc(story.id);
    if (ref == null) return;
    await ref.set({
      'publishedStoryId': story.id,
      'title': story.title,
      'tags': story.tags.toMap(),
      'authorUid': story.authorUid,
      'archivedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unarchive(String publishedStoryId) async {
    await _archiveDoc(publishedStoryId)?.delete();
  }

  Stream<bool> watchArchivedFlag(String publishedStoryId) {
    final ref = _archiveDoc(publishedStoryId);
    if (ref == null) return Stream.value(false);
    return ref.snapshots().map((s) => s.exists);
  }

  Stream<List<ArchivedStory>> watchArchived() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('users').doc(uid)
        .collection('archived')
        .orderBy('archivedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ArchivedStory.fromDoc).toList());
  }

  HttpsCallable _call(String name) => _functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return CommunityRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseFunctions.instanceFor(region: kFunctionsRegion),
  );
});

/// The signed-in user's saved (archived) community stories.
final archivedStoriesProvider =
    StreamProvider.autoDispose<List<ArchivedStory>>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(communityRepositoryProvider).watchArchived();
});
