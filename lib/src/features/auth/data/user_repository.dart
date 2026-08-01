import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads/writes the `users/{uid}` document.
class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Ensures `users/{uid}` exists after sign-in. Idempotent: sets `createdAt`
  /// only on first creation and merges on subsequent sign-ins.
  Future<void> ensureUserDocument(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    if (snapshot.exists) {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await ref.set({
        'email': user.email,
        'displayName': user.displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
        'settings': <String, dynamic>{},
      });
    }
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(FirebaseFirestore.instance);
});
