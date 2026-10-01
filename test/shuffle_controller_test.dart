import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/features/stories/domain/story.dart';
import 'package:kitty_story/src/features/community/domain/published_story.dart';

Story _story(String id) =>
    Story(id: id, source: StorySource.generated, title: 'S$id', text: 'x');

void main() {
  test('a saved community story adapts to something narratable', () {
    final saved = ArchivedStory(
      publishedStoryId: 'pub1',
      title: 'Tama',
      tags: const StoryTags(content: [], style: [], wisdom: []),
    );
    final story = saved.toStory();
    // Narration is resolved server-side from storyId + storySource, so those
    // two are the ones that have to survive the conversion.
    expect(story.id, 'pub1');
    expect(story.source, StorySource.published);
    expect(story.title, 'Tama');
  });

  test('shuffle pool combines both kinds of story the user owns', () {
    final generated = [_story('a'), _story('b')];
    final saved = [
      ArchivedStory(
        publishedStoryId: 'c',
        title: 'C',
        tags: const StoryTags(content: [], style: [], wisdom: []),
      ),
    ];
    final pool = <Story>[...generated, ...saved.map((s) => s.toStory())];
    expect(pool.map((s) => s.id), ['a', 'b', 'c']);
    // Samples are deliberately absent: "your stories" means the user's own.
    expect(pool.every((s) => s.source != StorySource.library), isTrue);
  });
}
