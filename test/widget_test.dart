import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/app.dart';

void main() {
  testWidgets('boots into the home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KittyStoryApp()));
    await tester.pumpAndSettle();

    expect(find.text('Kitty Stories'), findsWidgets);
    expect(find.text('Family voices'), findsOneWidget);
  });
}
