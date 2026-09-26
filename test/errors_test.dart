import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitty_story/src/common/errors.dart';

void main() {
  final quota = FirebaseException(
    plugin: 'firebase_functions',
    code: 'resource-exhausted',
    message: "You've reached the free plan's weekly limit.",
    stackTrace: StackTrace.current,
  );

  test('shows the server message, not the stack trace', () {
    // The guard is only meaningful if toString() really does leak frames.
    expect(quota.toString(), contains('#0'));
    expect(friendlyError(quota), "You've reached the free plan's weekly limit.");
  });

  test('falls back when there is nothing useful to say', () {
    expect(friendlyError(Exception('boom')), 'please try again.');
    expect(friendlyError(Exception('boom'), fallback: 'Nope.'), 'Nope.');
    final blank = FirebaseException(plugin: 'p', code: 'c', message: '');
    expect(friendlyError(blank), 'please try again.');
  });
}
