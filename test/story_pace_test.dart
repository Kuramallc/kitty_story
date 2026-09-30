import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/features/stories/data/story_repository.dart';

void main() {
  test('the default length still paces the bar to the measured 45s', () {
    // p90 of successful generations at the default length was 47s; the bar was
    // paced to 45s before length was selectable, and must not drift now that
    // it is computed.
    expect(storyGenerationPace(kDefaultStoryMinutes).inSeconds, 45);
  });

  test('longer stories get a longer bar', () {
    var previous = Duration.zero;
    for (var m = kMinStoryMinutes; m <= kMaxStoryMinutes; m++) {
      final pace = storyGenerationPace(m);
      expect(pace, greaterThan(previous), reason: 'pace must rise with length');
      previous = pace;
    }
  });

  test('even the shortest story gets a bar worth showing', () {
    // Below roughly this, the bar would be over before it read as progress.
    expect(storyGenerationPace(kMinStoryMinutes).inSeconds, greaterThan(20));
  });
}
