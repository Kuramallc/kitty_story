import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/common/widgets/parental_gate.dart';

void main() {
  testWidgets('parental gate blocks a wrong answer and passes a correct one',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result = await showParentalGate(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Ask a grown-up'), findsOneWidget);

    // Wrong answer keeps the gate open and doesn't resolve.
    await tester.enterText(find.byType(TextField), '-1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Ask a grown-up'), findsOneWidget);
    expect(result, isNull);

    // Read the current question, answer it correctly → gate passes.
    final question = tester.widget<Text>(find.textContaining('×')).data!;
    final m = RegExp(r'(\d+)\s*×\s*(\d+)').firstMatch(question)!;
    final answer = int.parse(m.group(1)!) * int.parse(m.group(2)!);
    await tester.enterText(find.byType(TextField), '$answer');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
