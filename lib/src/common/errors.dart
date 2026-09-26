import 'package:firebase_core/firebase_core.dart';

/// A calm, one-line message for an error we are about to show the user.
///
/// `FirebaseException.toString()` appends the captured stack trace, so
/// interpolating an error straight into UI text puts raw Dart frames in front
/// of a parent — which is what hitting the free weekly limit used to do. Take
/// the server's message instead, and say something plain for anything else,
/// since an unrecognized error has nothing useful to tell a reader anyway.
///
/// [fallback] completes the caller's sentence: the default is written to sit
/// after a "Could not ...:" prefix.
String friendlyError(
  Object error, {
  String fallback = 'please try again.',
}) {
  if (error is FirebaseException) {
    final message = error.message;
    if (message != null && message.isNotEmpty) return message;
  }
  return fallback;
}
