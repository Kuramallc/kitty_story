import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/explore_controller.dart';
import '../domain/published_story.dart';
import '../../../common/widgets/page_width.dart';

/// Community feed: filter by tags, sorted by likes, infinite scroll.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _scroll = ScrollController();
  final _tagInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
        ref.read(exploreControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim().toLowerCase();
    _tagInput.clear();
    if (tag.isEmpty) return;
    final current = ref.read(exploreControllerProvider).filterTags;
    if (!current.contains(tag) && current.length < 10) {
      ref.read(exploreControllerProvider.notifier).setFilter([...current, tag]);
    }
  }

  void _removeTag(String tag) {
    final current = ref.read(exploreControllerProvider).filterTags;
    ref
        .read(exploreControllerProvider.notifier)
        .setFilter(current.where((t) => t != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exploreControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: SafeArea(
        child: PageWidth(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _tagInput,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _addTag,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filter by a tag (e.g. animals, kindness)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (state.filterTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in state.filterTags)
                          InputChip(
                            label: Text(tag),
                            onDeleted: () => _removeTag(tag),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: _body(state)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ExploreState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        text: 'Couldn\'t load stories.',
        onRetry: () => ref.read(exploreControllerProvider.notifier).refresh(),
      );
    }
    if (state.items.isEmpty) {
      return _Message(
        icon: Icons.travel_explore,
        text: state.filterTags.isEmpty
            ? 'No published stories yet.\nBe the first to publish one!'
            : 'No stories match those tags.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(exploreControllerProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _Footer(
              state: state,
              onLoadMore: () =>
                  ref.read(exploreControllerProvider.notifier).loadMore(),
            );
          }
          return _StoryCard(story: state.items[index]);
        },
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final PublishedStory story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = story.text.replaceAll('\n', ' ');
    final tags = story.tags.all.take(4).toList();
    return Card(
      child: InkWell(
        onTap: () => context.push('/explore/story/${story.id}', extra: story),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(story.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: -6,
                  children: [
                    for (final t in tags)
                      Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.favorite,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text('${story.likeCount}', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.mode_comment_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${story.commentCount}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onLoadMore});

  final ExploreState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.hasMore) {
      return Center(
        child: TextButton(
          onPressed: onLoadMore,
          child: const Text('Load more'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'That\'s everything for now',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
