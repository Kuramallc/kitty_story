import 'package:cloud_firestore/cloud_firestore.dart';

import '../../stories/domain/story.dart';

/// Content / style / wisdom keyword tags for a community story.
class StoryTags {
  const StoryTags({
    this.content = const [],
    this.style = const [],
    this.wisdom = const [],
  });

  final List<String> content;
  final List<String> style;
  final List<String> wisdom;

  List<String> get all => [...content, ...style, ...wisdom];
  bool get isEmpty => content.isEmpty && style.isEmpty && wisdom.isEmpty;

  Map<String, dynamic> toMap() => {'content': content, 'style': style, 'wisdom': wisdom};

  factory StoryTags.fromMap(Map<String, dynamic>? m) => StoryTags(
        content: _list(m?['content']),
        style: _list(m?['style']),
        wisdom: _list(m?['wisdom']),
      );

  static List<String> _list(dynamic v) =>
      v is List ? v.whereType<String>().toList() : const [];
}

/// A story published to the shared community pool.
class PublishedStory {
  const PublishedStory({
    required this.id,
    required this.title,
    required this.text,
    required this.authorUid,
    required this.tags,
    required this.likeCount,
    required this.commentCount,
    this.status = 'published',
    this.createdAt,
  });

  final String id;
  final String title;
  final String text;
  final String authorUid;
  final StoryTags tags;
  final int likeCount;
  final int commentCount;

  /// "published" (visible), "under_review" (auto-hidden by reports), or
  /// "removed" (admin takedown). Explore only ever returns "published".
  final String status;
  final DateTime? createdAt;

  /// Adapts to a [Story] (published source) so it narrates via the existing
  /// story repository / synthesizeNarration path.
  Story toStory() => Story(
        id: id,
        source: StorySource.published,
        title: title,
        text: text,
      );

  factory PublishedStory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PublishedStory(
      id: doc.id,
      title: (d['title'] as String?) ?? 'Story',
      text: (d['text'] as String?) ?? '',
      authorUid: (d['authorUid'] as String?) ?? '',
      tags: StoryTags.fromMap(d['tags'] as Map<String, dynamic>?),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      status: (d['status'] as String?) ?? 'published',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A user's bookmark of a published story (their saved library).
class ArchivedStory {
  const ArchivedStory({
    required this.publishedStoryId,
    required this.title,
    required this.tags,
    this.archivedAt,
  });

  final String publishedStoryId;
  final String title;
  final StoryTags tags;
  final DateTime? archivedAt;

  factory ArchivedStory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ArchivedStory(
      publishedStoryId: (d['publishedStoryId'] as String?) ?? doc.id,
      title: (d['title'] as String?) ?? 'Story',
      tags: StoryTags.fromMap(d['tags'] as Map<String, dynamic>?),
      archivedAt: (d['archivedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A moderated comment on a community story.
class StoryComment {
  const StoryComment({
    required this.id,
    required this.authorUid,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String text;
  final DateTime? createdAt;

  factory StoryComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return StoryComment(
      id: doc.id,
      authorUid: (d['authorUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
