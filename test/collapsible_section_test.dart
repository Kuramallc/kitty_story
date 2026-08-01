import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/common/widgets/collapsible_section.dart';

void main() {
  testWidgets('CollapsibleSection collapses to its title and expands again',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CollapsibleSection(
            title: 'Sample stories',
            child: Text('BODY CONTENT'),
          ),
        ),
      ),
    );

    // Starts expanded: body visible, ✕ (collapse) affordance shown.
    expect(find.text('BODY CONTENT'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Collapse via the ✕ → body gone, title remains, expand affordance shown.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('BODY CONTENT'), findsNothing);
    expect(find.text('Sample stories'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Tapping the header title expands it again.
    await tester.tap(find.text('Sample stories'));
    await tester.pumpAndSettle();
    expect(find.text('BODY CONTENT'), findsOneWidget);
  });
}
