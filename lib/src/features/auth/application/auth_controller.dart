import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/user_repository.dart';

/// Drives sign-in/up/out actions and exposes their loading/error state to the
/// UI via [AsyncValue]. Routing reacts to the underlying FirebaseAuth stream,
/// so these methods don't navigate themselves.
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signInWithEmail(String email, String password) {
    return _run(() async {
      final cred = await ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: password);
      await _ensureUser(cred);
    });
  }

  Future<void> registerWithEmail(String email, String password) {
    return _run(() async {
      final cred = await ref
          .read(authRepositoryProvider)
          .registerWithEmail(email: email, password: password);
      await _ensureUser(cred);
    });
  }

  Future<void> signInWithGoogle() {
    return _run(() async {
      final cred = await ref.read(authRepositoryProvider).signInWithGoogle();
      await _ensureUser(cred);
    });
  }

  Future<void> signInWithApple() {
    return _run(() async {
      final cred = await ref.read(authRepositoryProvider).signInWithApple();
      await _ensureUser(cred);
    });
  }

  Future<void> signOut() => _run(() => ref.read(authRepositoryProvider).signOut());

  Future<void> _ensureUser(UserCredential? cred) async {
    final user = cred?.user;
    if (user != null) {
      await ref.read(userRepositoryProvider).ensureUserDocument(user);
    }
  }

  /// Runs [action], reflecting loading + errors in [state].
  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
