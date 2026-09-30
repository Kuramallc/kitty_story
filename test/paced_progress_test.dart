import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/common/widgets/paced_progress.dart';

double _value(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).value!;

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var spent = Duration.zero; spent < total; spent += step) {
    await tester.pump(step);
  }
}

Widget _host({required bool done}) => MaterialApp(
      home: Scaffold(
        body: PacedProgress(
          done: done,
          messages: const ['first', 'second', 'third'],
        ),
      ),
    );

void main() {
  testWidgets('crawls forward but never fills on its own', (tester) async {
    await tester.pumpWidget(_host(done: false));

    await _pumpFor(tester, const Duration(seconds: 3));
    final early = _value(tester);
    expect(early, greaterThan(0.0));

    await _pumpFor(tester, const Duration(seconds: 7));
    final atTen = _value(tester);
    expect(atTen, greaterThan(early), reason: 'should keep advancing');
    expect(atTen, greaterThan(0.6), reason: 'should feel nearly there by 10s');

    // The point of the ceiling: a slow backend must never leave a full bar
    // sitting there, which reads as a hang.
    await _pumpFor(tester, const Duration(seconds: 40));
    expect(_value(tester), lessThan(1.0));

    await tester.pumpWidget(_host(done: false)); // settle timers
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fills only when the caller says the work is done',
      (tester) async {
    await tester.pumpWidget(_host(done: false));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(_value(tester), lessThan(1.0));

    await tester.pumpWidget(_host(done: true));
    // The bar glides to full rather than snapping, so let the tween land.
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(_value(tester), 1.0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a longer duration paces the crawl slower', (tester) async {
    // The screen passes 45s because generation really takes that long. If the
    // duration stopped being honoured the bar would race to the ceiling and
    // park, which is what it exists to avoid.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PacedProgress(done: false, duration: Duration(seconds: 45)),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 10));
    final slow = _value(tester);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(_host(done: false)); // default 10s
    await _pumpFor(tester, const Duration(seconds: 10));
    final fast = _value(tester);
    await tester.pumpWidget(const SizedBox());

    expect(slow, lessThan(fast),
        reason: 'at the same wall-clock, 45s pacing must be further behind');
  });

  testWidgets('stays hidden until revealAfter has passed', (tester) async {
    // Narration is usually a cache hit returning in ~0.1s. Showing the bar
    // immediately would flash it for a frame on the majority of taps.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PacedProgress(
            done: false,
            revealAfter: Duration(milliseconds: 600),
          ),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'still inside the reveal delay');

    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'reveal delay has passed');

    // The pacing clock runs while hidden, so it appears where the elapsed
    // time says it should be rather than snapping back to zero.
    expect(_value(tester), greaterThan(0.0));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('never shows two messages at once', (tester) async {
    // Regression: a plain cross-fade stacks the outgoing and incoming lines,
    // and two centred strings of different lengths fading through each other
    // render as one unreadable smear. Caught on device.
    await tester.pumpWidget(_host(done: false));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final visible = tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(AnimatedSwitcher),
              matching: find.byType(FadeTransition),
            ),
          )
          .where((f) => f.opacity.value > 0.05)
          .length;
      expect(visible, lessThanOrEqualTo(1),
          reason: 'two messages visible together at step $i');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rotates through the messages while waiting', (tester) async {
    await tester.pumpWidget(_host(done: false));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    await _pumpFor(tester, const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
