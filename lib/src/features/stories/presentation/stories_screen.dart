import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/collapsible_section.dart';
import '../../community/data/community_repository.dart';
import '../../community/domain/published_story.dart';
import '../data/story_repository.dart';
import '../domain/story.dart';
import 'story_cards.dart';

/// Sections show at most this many stories inline; the rest are behind
/// that section's "View all" button.
const int _kSectionPreviewCount = 3;

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
            child: _SectionPreview<Story>(
              items: createdStories,
              cardBuilder: (s) => StoryCard(story: s),
              viewAllRoute: '/stories/created',
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
            : _SectionPreview<ArchivedStory>(
                items: list,
                cardBuilder: (i) => ArchivedStoryCard(item: i),
                viewAllRoute: '/stories/community',
              ),
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
            : _SectionPreview<Story>(
                items: list,
                cardBuilder: (s) => StoryCard(story: s),
                viewAllRoute: '/stories/sample',
              ),
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

/// The first [_kSectionPreviewCount] cards of a section, plus a "View all"
/// button underneath when there are more than that to see.
class _SectionPreview<T> extends StatelessWidget {
  const _SectionPreview({
    super.key,
    required this.items,
    required this.cardBuilder,
    required this.viewAllRoute,
  });

  final List<T> items;
  final Widget Function(T item) cardBuilder;
  final String viewAllRoute;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(_kSectionPreviewCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: cardBuilder(item),
          ),
        if (items.length > _kSectionPreviewCount)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(viewAllRoute),
              child: const Text('View all'),
            ),
          ),
      ],
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
