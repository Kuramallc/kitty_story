import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitty_story/src/bootstrap.dart';

/// Live end-to-end check of Phase 1 against the real Firebase project:
/// boot → redirected to sign-in → register with email/password → home shows
/// the signed-in user → users/{uid} doc exists in Firestore → cleanup
/// (delete doc + auth account) → redirected back to sign-in.
///
/// Requires Email/Password enabled and a Firestore database created in the
/// Firebase console (SETUP.md §1).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register → user doc → delete → signed out', (tester) async {
    await bootstrap();

    // Signed out, so the router must land us on the sign-in screen.
    await _pumpUntil(tester, find.text('Create an account'));

    final email =
        'kitty.itest.${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'Test123456!';

    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.text('Create an account'));

    // Registration + redirect: home greets the signed-in user.
    await _pumpUntil(
      tester,
      find.textContaining('Signed in as'),
      timeout: const Duration(seconds: 60),
    );

    final user = FirebaseAuth.instance.currentUser;
    expect(user, isNotNull, reason: 'FirebaseAuth should have a current user');
    expect(user!.email, email);

    // The auth controller writes users/{uid} after sign-in; poll briefly.
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      snapshot = await docRef.get();
      if (snapshot.exists) break;
      await tester.pump(const Duration(seconds: 1));
    }
    expect(snapshot?.exists, isTrue, reason: 'users/{uid} doc should exist');
    expect(snapshot!.data()!['email'], email);

    // Cleanup the test account, which also exercises signed-out redirect.
    await docRef.delete();
    await user.delete();
    await _pumpUntil(tester, find.text('Create an account'));
  });
}

/// Pumps real frames until [finder] matches or [timeout] elapses. Avoids
/// pumpAndSettle, which would hang on the indefinite progress spinner.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}
