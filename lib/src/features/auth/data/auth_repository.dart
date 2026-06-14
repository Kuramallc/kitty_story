import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Optional OAuth **web** client id (Firebase console → Project settings → your
/// apps, or `google-services.json` `client_type: 3`). Required on Android for
/// Google Sign-In to return an ID token Firebase will accept. Fill this in
/// during SETUP.md §3; leave `null` until then.
const String? googleServerClientId = null;

/// Thin wrapper over [FirebaseAuth] with the sign-in methods the app supports.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;
  bool _googleInitialized = false;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  /// Interactive Google sign-in. Returns `null` if the user cancels.
  Future<UserCredential?> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: googleServerClientId);
      _googleInitialized = true;
    }
    if (!google.supportsAuthenticate()) {
      throw UnsupportedError('Google Sign-In is not supported on this platform.');
    }

    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google did not return an ID token. On Android set '
            'googleServerClientId (SETUP.md §3).',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  /// Interactive Apple sign-in. Returns `null` if the user cancels.
  Future<UserCredential?> signInWithApple() async {
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    // Best-effort Google sign-out so the account chooser reappears next time.
    try {
      if (_googleInitialized) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Ignore — Firebase sign-out below is what matters.
    }
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

/// Emits the current [User] (or null) and updates on sign-in/out.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});
