import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitty_story/src/features/community/data/community_repository.dart';
import 'package:kitty_story/src/features/community/domain/published_story.dart';
import 'package:kitty_story/src/features/stories/data/story_repository.dart';
import 'package:kitty_story/src/features/stories/domain/story.dart';
import 'package:kitty_story/src/features/stories/presentation/story_cards.dart';
import 'package:kitty_story/src/features/stories/presentation/story_section_list_screen.dart';
import 'package:kitty_story/src/features/stories/presentation/stories_screen.dart';

Story _story(int n) => Story(
      id: 'created-$n',
      source: StorySource.generated,
      title: 'Created story $n',
      text: 'Once upon a time, story number $n.',
    );

Story _sample(int n) => Story(
      id: 'sample-$n',
      source: StorySource.library,
      title: 'Sample story $n',
      text: 'A classic bedtime tale, number $n.',
    );

ArchivedStory _archived(int n) => ArchivedStory(
      publishedStoryId: 'community-$n',
      title: 'Community story $n',
      tags: const StoryTags(),
    );

/// A minimal router mirroring the app's real Stories routes, so "View all"
/// navigation can be exercised without pulling in auth/Firebase wiring.
GoRouter _testRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const StoriesScreen()),
        GoRoute(
          path: '/stories/created',
          builder: (context, state) => SectionListScreen<Story>(
            title: 'Created by me',
            watch: (ref) => ref.watch(myStoriesProvider),
            cardBuilder: (s) => StoryCard(story: s),
            emptyMessage: 'Stories you\'ve made will appear here.',
          ),
        ),
        GoRoute(
          path: '/stories/community',
          builder: (context, state) => SectionListScreen<ArchivedStory>(
            title: 'Community',
            watch: (ref) => ref.watch(archivedStoriesProvider),
            cardBuilder: (i) => ArchivedStoryCard(item: i),
            emptyMessage: 'Tap Play on a story in Explore to save it here.',
          ),
        ),
        GoRoute(
          path: '/stories/sample',
          builder: (context, state) => SectionListScreen<Story>(
            title: 'Sample',
            watch: (ref) => ref.watch(libraryStoriesProvider),
            cardBuilder: (s) => StoryCard(story: s),
            emptyMessage: 'Curated stories will appear here.',
          ),
        ),
        // Card taps target these; not exercised in these tests, but routing
        // to an unknown path would throw, so keep them registered.
        GoRoute(
          path: '/stories/detail',
          builder: (context, state) => const Scaffold(body: Text('detail')),
        ),
        GoRoute(
          path: '/explore/story/:id',
          builder: (context, state) => const Scaffold(body: Text('explore detail')),
        ),
        GoRoute(
          path: '/stories/generate',
          builder: (context, state) => const Scaffold(body: Text('generate')),
        ),
      ],
    );

void main() {
  // 5 created, 2 community (saved), 4 sample — exercises both sides of the
  // "more than 3" threshold in the same pump.
  final created = [for (var i = 1; i <= 5; i++) _story(i)];
  final community = [for (var i = 1; i <= 2; i++) _archived(i)];
  final sample = [for (var i = 1; i <= 4; i++) _sample(i)];

  /// Tall enough that every section's cards are actually built (Sliver lists
  /// only build what's within the viewport + cache extent), so `find.text`
  /// can see them without needing to scroll mid-test.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        myStoriesProvider.overrideWith((ref) => Stream.value(created)),
        archivedStoriesProvider.overrideWith((ref) => Stream.value(community)),
        libraryStoriesProvider.overrideWith((ref) => Stream.value(sample)),
      ],
      child: MaterialApp.router(routerConfig: _testRouter()),
    );
  }

  testWidgets(
      'sections show at most 3 cards, with View all only past the threshold',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Created by me (5 items): only the first 3 inline, "View all" shown.
    expect(find.text('Created story 1'), findsOneWidget);
    expect(find.text('Created story 3'), findsOneWidget);
    expect(find.text('Created story 4'), findsNothing);
    expect(find.text('Created story 5'), findsNothing);

    // Community (2 items, under the threshold): both shown, no "View all".
    expect(find.text('Community story 1'), findsOneWidget);
    expect(find.text('Community story 2'), findsOneWidget);

    // Sample (4 items): only the first 3 inline, "View all" shown.
    expect(find.text('Sample story 1'), findsOneWidget);
    expect(find.text('Sample story 3'), findsOneWidget);
    expect(find.text('Sample story 4'), findsNothing);

    // Exactly the two over-threshold sections (Created, Sample) get a button.
    expect(find.widgetWithText(TextButton, 'View all'), findsNWidgets(2));
  });

  testWidgets('View all opens the full list for that section', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // "Created by me" renders first, so its "View all" is the first match.
    await tester.tap(find.widgetWithText(TextButton, 'View all').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Created by me'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.text('Created story $i'), findsOneWidget);
    }
  });
}
