import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../auth/data/auth_repository.dart';

/// RevenueCat **public** SDK keys, injected at build time. Production keys are
/// per-store, so pass whichever platforms you're building:
///   --dart-define=REVENUECAT_IOS_API_KEY=appl_xxxxx
///   --dart-define=REVENUECAT_ANDROID_API_KEY=goog_xxxxx
/// REVENUECAT_API_KEY is a single-key fallback for both platforms (that's what a
/// `test_…` Test Store key needs, since it isn't store-specific).
/// Never use a secret key (`sk_…`) here — those are server-only.
const String _iosApiKey = String.fromEnvironment('REVENUECAT_IOS_API_KEY');
const String _androidApiKey = String.fromEnvironment('REVENUECAT_ANDROID_API_KEY');
const String _sharedApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

/// The key for the current platform, or empty when none was provided — in which
/// case the subscription layer no-ops (everyone is free tier, no paywall
/// offering is shown). See SETUP.md.
String get revenueCatApiKey {
  final platformKey = Platform.isIOS
      ? _iosApiKey
      : Platform.isAndroid
          ? _androidApiKey
          : '';
  return platformKey.isNotEmpty ? platformKey : _sharedApiKey;
}

/// Entitlement identifier configured in the RevenueCat dashboard.
const String kUnlimitedEntitlement = 'unlimited';

/// Free-tier voice-profile cap (mirrors FREE_MAX_VOICES in functions/config.ts);
/// used to gate the "Add a voice" button before recording.
const int kFreeMaxVoices = 3;

/// True when the configured key can't be used in this build. A `test_…` Test
/// Store key is **debug-only** — the native SDK hard-fails on it in a release
/// build, which crashes the app at launch — and a key for the other store is
/// equally unusable.
bool get _keyUnusableHere {
  final key = revenueCatApiKey;
  if (key.startsWith('test_')) return kReleaseMode;
  final expected = Platform.isIOS ? 'appl_' : 'goog_';
  return !key.startsWith(expected);
}

/// Configure RevenueCat once at startup. Subscriptions are optional, so this
/// never throws and never blocks startup: on any problem the app simply runs
/// free-tier-only (no paywall) rather than failing to launch.
Future<void> configureRevenueCat() async {
  if (revenueCatApiKey.isEmpty) return;
  if (_keyUnusableHere) {
    debugPrint(
      'RevenueCat: skipping configure — this API key is not usable in this '
      'build (Test Store keys are debug-only; store keys must match the '
      'platform). Running free-tier-only.',
    );
    return;
  }
  try {
    await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
  } catch (error) {
    debugPrint('RevenueCat not configured (free-tier-only): $error');
  }
}

/// Thin wrapper over the RevenueCat SDK. The backend (limits.ts) is the source
/// of truth for *enforcement* via the webhook-synced Firestore flag; this is the
/// client-side view used to drive the paywall UI.
class SubscriptionRepository {
  bool get isConfigured => revenueCatApiKey.isNotEmpty && !_keyUnusableHere;

  /// Tie purchases to the Firebase uid (so the webhook can map them to a user).
  Future<void> linkUser(String uid) async {
    if (!isConfigured) return;
    try {
      await Purchases.logIn(uid);
    } catch (_) {/* non-fatal */}
  }

  Future<void> unlinkUser() async {
    if (!isConfigured) return;
    try {
      await Purchases.logOut();
    } catch (_) {/* non-fatal */}
  }

  bool _hasEntitlement(CustomerInfo info) =>
      info.entitlements.active.containsKey(kUnlimitedEntitlement);

  /// Whether the unlimited entitlement is active. Emits a single `false` when
  /// RevenueCat isn't configured.
  Stream<bool> entitlement() {
    if (!isConfigured) return Stream<bool>.value(false);
    final controller = StreamController<bool>();
    void listener(CustomerInfo info) => controller.add(_hasEntitlement(info));
    Purchases.addCustomerInfoUpdateListener(listener);
    Purchases.getCustomerInfo()
        .then((info) => controller.add(_hasEntitlement(info)))
        .catchError((_) {});
    controller.onCancel = () {
      Purchases.removeCustomerInfoUpdateListener(listener);
      controller.close();
    };
    return controller.stream;
  }

  /// The active subscription offering, or null when none is available
  /// (RevenueCat unconfigured, or no product for this storefront/region).
  Future<Offering?> currentOffering() async {
    if (!isConfigured) return null;
    try {
      return (await Purchases.getOfferings()).current;
    } catch (_) {
      return null;
    }
  }

  /// Purchases [package]; returns whether it granted the entitlement.
  Future<bool> purchase(Package package) async {
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return _hasEntitlement(result.customerInfo);
  }

  /// Restores prior purchases; returns whether the entitlement is now active.
  Future<bool> restore() async {
    final info = await Purchases.restorePurchases();
    return _hasEntitlement(info);
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository();
});

/// Whether the signed-in user currently has the unlimited entitlement
/// (client-side view; the backend reads the webhook-synced Firestore flag).
final entitlementActiveProvider = StreamProvider<bool>((ref) {
  return ref.watch(subscriptionRepositoryProvider).entitlement();
});

/// Keeps RevenueCat's identified user in sync with Firebase auth. Watch once
/// from the root widget to activate it.
final subscriptionSyncProvider = Provider<void>((ref) {
  final repo = ref.watch(subscriptionRepositoryProvider);
  ref.listen(authStateChangesProvider, (_, next) {
    final user = next.value;
    if (user != null) {
      repo.linkUser(user.uid);
    } else {
      repo.unlinkUser();
    }
  }, fireImmediately: true);
});
