import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../auth/data/auth_repository.dart';

/// RevenueCat public SDK key, injected at build time:
///   --dart-define=REVENUECAT_API_KEY=appl_xxxxx
/// Empty in dev/test → the subscription layer no-ops (everyone is free tier and
/// no paywall offering is shown). See SETUP.md.
const String revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

/// Entitlement identifier configured in the RevenueCat dashboard.
const String kUnlimitedEntitlement = 'unlimited';

/// Free-tier voice-profile cap (mirrors FREE_MAX_VOICES in functions/config.ts);
/// used to gate the "Add a voice" button before recording.
const int kFreeMaxVoices = 3;

/// Configure RevenueCat once at startup. No-op (and never throws) when the key
/// is absent, so the app still runs in dev without RevenueCat set up.
Future<void> configureRevenueCat() async {
  if (revenueCatApiKey.isEmpty) return;
  try {
    await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
  } catch (_) {
    // Non-fatal: the app falls back to free-tier-only behavior.
  }
}

/// Thin wrapper over the RevenueCat SDK. The backend (limits.ts) is the source
/// of truth for *enforcement* via the webhook-synced Firestore flag; this is the
/// client-side view used to drive the paywall UI.
class SubscriptionRepository {
  bool get isConfigured => revenueCatApiKey.isNotEmpty;

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
