import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/theme/app_theme.dart';

void main() {
  // Regression: the FilledButton theme must not force an infinite min width,
  // or FilledButtons placed in a Row (e.g. the community detail action bar and
  // the player controls) fail to lay out and the screen renders blank.
  testWidgets('FilledButton lays out inside a Row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: Row(
            children: [
              const Text('left'),
              const Spacer(),
              FilledButton(onPressed: () {}, child: const Text('Play')),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Play'), findsOneWidget);
  });
}
