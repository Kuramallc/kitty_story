# Kitty Story — Setup

This covers the **credential / account steps that must be done by a human** (they need
your Google, Apple, ElevenLabs, and Anthropic accounts). Everything else — the Flutter app,
Cloud Functions, security rules, and native config — is already scaffolded.

After finishing the **Required** section, the app will boot past the "Firebase isn't
configured yet" notice and you can start Phase 1 (auth).

---

## 0. One-time tooling note

The FlutterFire CLI is installed but lives in `~/.pub-cache/bin`. Put it on your PATH:

```bash
echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.zshrc && source ~/.zshrc
flutterfire --version   # verify
```

(Or run it without PATH changes: `dart pub global run flutterfire_cli:flutterfire ...`.)

App identifiers already set in this project:
- **Android applicationId / namespace:** `com.kuramallc.kitty_story`
- **iOS bundle id:** set in Xcode (`PRODUCT_BUNDLE_IDENTIFIER`) — pick one, e.g. `com.kuramallc.kittyStory`.

---

## 1. Required — connect Firebase

1. **Log in & create the project**
   ```bash
   firebase login
   firebase projects:create kitty-story        # or create it in the Firebase console
   ```

2. **Wire the app to it** (generates `lib/firebase_options.dart` and registers the
   iOS/Android apps automatically):
   ```bash
   flutterfire configure --project=kitty-story
   ```
   Select iOS + Android when prompted. This generates `lib/firebase_options.dart` for the app.

3. **Enable products** in the [Firebase console](https://console.firebase.google.com):
   - **Authentication** → Sign-in method → enable **Email/Password**, **Google**, **Apple**.
   - **Firestore Database** → create (production mode is fine; our rules apply).
   - **Storage** → enable.
   - **App Check** → register the apps (you'll add real providers in Phase 5; debug works now).

4. **Run it:**
   ```bash
   flutter run
   ```
   The home screen's setup notice should be gone.

---

## 2. Required — Cloud Function secrets

The backend calls ElevenLabs (voice cloning + TTS) and Claude (story text). Keys live only
in the backend via Secret Manager — never in the app.

```bash
firebase functions:secrets:set ELEVENLABS_API_KEY     # paste your ElevenLabs API key
firebase functions:secrets:set ANTHROPIC_API_KEY      # paste your Anthropic API key
```

- **ElevenLabs:** create an account at elevenlabs.io and generate an API key.
  ⚠️ **Multi-tenant consent (resolve before Phase 2 ships):** confirm ElevenLabs' terms +
  API path for end users cloning *their own* voices under our account, and how their
  consent/verification requirement is satisfied. The app already plans a consent screen +
  recorded consent statement to match this.
- **Anthropic:** get an API key at console.anthropic.com. Model used: `claude-sonnet-4-6`
  (configurable in `functions/src/config.ts`).

Deploy backend pieces when ready:
```bash
firebase deploy --only firestore:rules,storage:rules
firebase deploy --only functions
```

---

## 3. Platform sign-in extras (needed once you build Phase 1 auth)

- **Google Sign-In (Android):** add your debug + release **SHA-1/SHA-256** fingerprints to the
  Android app in Firebase console, then re-download `google-services.json` (flutterfire handles
  placement).
- **Google Sign-In (iOS):** add the reversed-client-id URL scheme to the iOS app (from
  `GoogleService-Info.plist`).
- **Sign in with Apple:** enable the **Sign in with Apple** capability in Xcode (Runner target →
  Signing & Capabilities) and in your Apple Developer account.

---

## 4. Local development with emulators (optional but recommended)

```bash
npm --prefix functions run build
firebase emulators:start
```

Then set `_useEmulators = true` in [`lib/src/bootstrap.dart`](lib/src/bootstrap.dart) and
re-run the app. Ports: Auth 9099 · Firestore 8080 · Storage 9199 · Functions 5001 · UI 4000.

**App Check debug token:** on first debug run the app prints a debug token in the console —
register it under App Check → Manage debug tokens so callable functions accept your dev device.

---

## Quick reference

| Thing | Where |
|---|---|
| Firebase init (guarded) | `lib/src/bootstrap.dart` |
| Generated Firebase config | `lib/firebase_options.dart` (after `flutterfire configure`) |
| Cloud Functions | `functions/src/` |
| Secrets | `functions/src/config.ts` (names only) + Secret Manager |
| Security rules | `firestore.rules`, `storage.rules` |
| Emulator config | `firebase.json` |
