import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Whether the signed-in user still needs to verify their email address.
///
/// Firebase pushes nothing when the user clicks the link in the email — the
/// cached ID token simply keeps saying `email_verified: false` — so this is
/// refreshed explicitly by [refresh] rather than streamed. Every screen that
/// shows verification UI watches this, so verifying in one place clears it
/// everywhere at once.
class EmailVerificationNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Re-evaluate on sign-in/out; the value itself is a one-shot read.
    ref.watch(authStateChangesProvider);
    return ref.read(authRepositoryProvider).needsEmailVerification;
  }

  /// Re-reads the user and mints a fresh ID token. Returns true once verified.
  Future<bool> refresh() async {
    final repo = ref.read(authRepositoryProvider);
    final verified = await repo.refreshUser();
    state = repo.needsEmailVerification;
    return verified;
  }

  Future<void> resend() => ref.read(authRepositoryProvider).sendEmailVerification();
}

final emailVerificationNeededProvider =
    NotifierProvider<EmailVerificationNotifier, bool>(EmailVerificationNotifier.new);
