import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Firebase initialized successfully at startup.
///
/// Overridden in `bootstrap()` with the real value. Defaults to `false` so
/// widget tests (which don't initialize Firebase) render the "setup" state.
final firebaseReadyProvider = Provider<bool>((ref) => false);
