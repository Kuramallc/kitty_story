import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/data/community_repository.dart';
import '../../community/domain/published_story.dart';
import '../data/story_repository.dart';
import '../domain/story.dart';
import '../../../common/errors.dart';

/// Confirms, then permanently deletes one of the user's own generated stories.
///
/// Gated behind a confirmation because it cannot be undone: the story and every
/// narration recorded from it are gone for good.
///
/// Returns true only when the story is actually gone, so a caller showing that
/// story can close itself — and stays put if the user backed out or the delete
/// failed.
Future<bool> confirmDeleteStory(
  BuildContext context,
  WidgetRef ref,
  Story story,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "${story.title}"?'),
      content: const Text(
        'This removes the story and any narration audio made from it. '
        'It cannot be undone.\n\n'
        'If you shared this story to the community, that copy stays there.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(storyRepositoryProvider).deleteGeneratedStory(story.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted "${story.title}".')),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not delete the story: ${friendlyError(error)}')),
    );
    return false;
  }
}

/// Removes a saved community story from the user's list.
///
/// No confirmation, because nothing is destroyed — the story stays in the
/// community and this only drops the bookmark. An Undo is offered instead,
/// which is friendlier than a dialog for something this reversible.
Future<void> removeSavedStory(
  BuildContext context,
  WidgetRef ref,
  ArchivedStory item,
) async {
  final repo = ref.read(communityRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.unarchive(item.publishedStoryId);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed "${item.title}".'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.rearchive(item),
        ),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not remove the story: ${friendlyError(error)}')),
    );
  }
}
