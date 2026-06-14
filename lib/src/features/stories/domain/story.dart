import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a story came from. Must match the `storySource` the
/// `synthesizeNarration` Cloud Function expects.
enum StorySource {
  library,
  generated;

  String get key => name; // "library" | "generated"
}

/// A bedtime story — either curated (shared `stories/`) or AI-generated
/// (`users/{uid}/generatedStories/`).
class Story {
  const Story({
    required this.id,
    required this.source,
    required this.title,
    required this.text,
    this.ageRange,
    this.coverImageUrl,
    this.createdAt,
  });

  final String id;
  final StorySource source;
  final String title;
  final String text;
  final String? ageRange;
  final String? coverImageUrl;
  final DateTime? createdAt;

  factory Story.fromLibraryDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Story(
      id: doc.id,
      source: StorySource.library,
      title: (data['title'] as String?) ?? 'Story',
      text: (data['text'] as String?) ?? '',
      ageRange: data['ageRange'] as String?,
      coverImageUrl: data['coverImageUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory Story.fromGeneratedDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final prompt = (data['prompt'] as Map<String, dynamic>?) ?? const {};
    return Story(
      id: doc.id,
      source: StorySource.generated,
      title: (data['title'] as String?) ?? 'My story',
      text: (data['text'] as String?) ?? '',
      ageRange: prompt['ageRange'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
