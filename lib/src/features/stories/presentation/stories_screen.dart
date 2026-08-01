import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/collapsible_section.dart';
import '../../community/data/community_repository.dart';
import '../../community/domain/published_story.dart';
import '../data/story_repository.dart';
import '../domain/story.dart';

/// The unified Library: one scrolling view of collapsible sections, in order:
///   • **Created by me** — the user's AI-generated stories. Pinned to the top,
///     but hidden entirely when they have none.
///   • **Community** — stories the user saved from Explore.
///   • **Sample** — a curated starter set, always pinned to the bottom.
///
/// A FAB opens the generation form (new stories land in "Created by me").
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/stories/generate'),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Create a story'),
      ),
      body: const SafeArea(child: _LibraryView()),
    );
  }
}

class _LibraryView extends ConsumerWidget {
  const _LibraryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final created = ref.watch(myStoriesProvider);
    final community = ref.watch(archivedStoriesProvider);
    final sample = ref.watch(libraryStoriesProvider);

    // "Created by me" is pinned to the top — but only when the user actually
    // has generated stories. While loading or on error there's nothing to show,
    // so it stays hidden (valueOrNull is null until data arrives).
    final createdStories = created.asData?.value ?? const <Story>[];
    final Widget? createdSection = createdStories.isEmpty
        ? null
        : CollapsibleSection(
            title: 'Created by me',
            subtitle: 'Stories you\'ve made',
            child: _CardColumn(
              children: [for (final s in createdStories) _StoryCard(story: s)],
            ),
          );

    final communitySection = CollapsibleSection(
      title: 'Community',
      subtitle: 'Stories you saved from the community',
      child: community.when(
        loading: () => const _SectionLoader(),
        error: (_, _) =>
            const _SectionMessage('Could not load your saved stories.'),
        data: (list) => list.isEmpty
            ? const _SectionMessage(
                'Tap Play on a story in Explore to save it here.')
            : _CardColumn(children: [for (final i in list) _ArchivedCard(item: i)]),
      ),
    );

    // Sample is always rendered last.
    final sampleSection = CollapsibleSection(
      title: 'Sample',
      subtitle: 'Bedtime classics to get you started',
      child: sample.when(
        loading: () => const _SectionLoader(),
        error: (_, _) => const _SectionMessage('Could not load sample stories.'),
        data: (list) => list.isEmpty
            ? const _SectionMessage('Curated stories will appear here.')
            : _CardColumn(children: [for (final s in list) _StoryCard(story: s)]),
      ),
    );

    final sections = <Widget>[
      ?createdSection,
      communitySection,
      sampleSection,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          sections[i],
        ],
      ],
    );
  }
}

/// Stacks cards with consistent spacing inside a collapsible section.
class _CardColumn extends StatelessWidget {
  const _CardColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
      ],
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final Story story;

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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/stories/detail', extra: story),
      ),
    );
  }
}

class _ArchivedCard extends StatelessWidget {
  const _ArchivedCard({required this.item});

  final ArchivedStory item;

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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/explore/story/${item.publishedStoryId}'),
      ),
    );
  }
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
