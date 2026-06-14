import 'package:audio_service/audio_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kitty_story/firebase_options.dart';

import 'app.dart';
import 'common/providers/firebase_providers.dart';
import 'features/player/application/audio_providers.dart';
import 'features/player/audio/audio_handler.dart';

/// Flip to `true` while running the local Firebase emulator suite
/// (`firebase emulators:start`). See SETUP.md.
const bool _useEmulators = false;

/// App entry point. Initializes Firebase + App Check, then runs the app.
///
/// Firebase init is guarded: before you run `flutterfire configure` (see
/// SETUP.md) there is no real `firebase_options.dart`, so initialization
/// fails gracefully and the app still boots into a "setup needed" home.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Debug providers for development. Switch to Play Integrity (Android) and
    // App Attest / DeviceCheck (Apple) for release builds — see SETUP.md.
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidDebugProvider(),
      providerApple: const AppleDebugProvider(),
    );
    if (_useEmulators) {
      await _connectToEmulators();
    }
    firebaseReady = true;
  } catch (error, stackTrace) {
    // Expected until `flutterfire configure` has been run.
    debugPrint('Firebase not initialized yet: $error');
    if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
  }

  // Background-capable audio handler for the bedtime player. Guarded so a
  // failure here never blocks app startup.
  StoryAudioHandler? audioHandler;
  try {
    audioHandler = await AudioService.init(
      builder: StoryAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.kuramallc.kitty_story.audio',
        androidNotificationChannelName: 'Story playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('AudioService init failed: $error');
    if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
  }

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        if (audioHandler != null)
          audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const KittyStoryApp(),
    ),
  );
}

/// Point the Firebase SDKs at the local emulator suite. The Android emulator
/// reaches the host machine via 10.0.2.2; everything else uses localhost.
Future<void> _connectToEmulators() async {
  final host =
      defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
}
