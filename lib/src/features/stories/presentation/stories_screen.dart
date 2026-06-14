import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/widgets/async_value_widget.dart';
import '../data/story_repository.dart';
import '../domain/story.dart';

/// Two tabs: the curated library and the user's AI-generated stories. A FAB
/// opens the generation form.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stories'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Library'), Tab(text: 'My stories')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/stories/generate'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Create a story'),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _StoryList(library: true),
              _StoryList(library: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryList extends ConsumerWidget {
  const _StoryList({required this.library});

  final bool library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(library ? libraryStoriesProvider : myStoriesProvider);
    return AsyncValueWidget(
      value: stories,
      data: (list) => list.isEmpty
          ? _EmptyState(library: library)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _StoryCard(story: list[index]),
            ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.library});

  final bool library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              library ? Icons.menu_book_outlined : Icons.auto_awesome,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              library ? 'No library stories yet' : 'No stories of your own yet',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              library
                  ? 'Curated bedtime stories will appear here.'
                  : 'Tap "Create a story" to make a personalized one.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
