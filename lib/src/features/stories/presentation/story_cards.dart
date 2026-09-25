import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../community/domain/published_story.dart';
import '../domain/story.dart';

/// A generated/library story row — used on the Stories home and on each
/// section's "View all" list.
class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.story, this.onDelete});

  final Story story;

  /// Shows a delete button when provided. Only the user's own generated
  /// stories pass this — the curated Sample library isn't theirs to remove.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = story.text.replaceAll('\n', ' ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            story.source == StorySource.library
                ? Icons.menu_book_outlined
                : Icons.auto_awesome,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(story.title, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete story',
                color: theme.colorScheme.error,
                onPressed: onDelete,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push('/stories/detail', extra: story),
      ),
    );
  }
}

/// A saved community-story row — used on the Stories home and on the
/// Community section's "View all" list.
class ArchivedStoryCard extends StatelessWidget {
  const ArchivedStoryCard({super.key, required this.item, this.onRemove});

  final ArchivedStory item;

  /// Shows a "remove from saved" button when provided. This only drops the
  /// bookmark — the story stays in the community.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = item.tags.all.take(3).join(' · ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.bookmark, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(item.title, style: theme.textTheme.titleMedium),
        subtitle: tags.isEmpty ? null : Text(tags),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.bookmark_remove_outlined),
                tooltip: 'Remove from saved',
                onPressed: onRemove,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push('/explore/story/${item.publishedStoryId}'),
      ),
    );
  }
}
