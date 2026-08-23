import { timingSafeEqual } from "node:crypto";

import { getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";

import { REGION, REVENUECAT_WEBHOOK_AUTH } from "./config";

// Event types that grant access vs. revoke it. CANCELLATION means "won't renew"
// but access continues until expiry, so it stays active.
const ACTIVATING = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
  "PRODUCT_CHANGE",
]);
const DEACTIVATING = new Set(["EXPIRATION", "BILLING_ISSUE"]);

/**
 * RevenueCat webhook → entitlement sync. RevenueCat is the source of truth for
 * purchases; we mirror active/expiry into `users/{uid}.subscription` so the
 * quota layer (limits.ts) can read it. `app_user_id` is the Firebase uid (set
 * client-side via Purchases.logIn).
 *
 * Secured by the shared secret configured in RevenueCat → Project → Webhooks
 * (Authorization header). Set it with:
 *   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH
 */
export const revenueCatWebhook = onRequest(
  { region: REGION, secrets: [REVENUECAT_WEBHOOK_AUTH] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    if (!isAuthorized(req.get("Authorization"))) {
      res.status(401).send("Unauthorized");
      return;
    }

    const event = req.body?.event;
    const uid: string | undefined = event?.app_user_id;
    const type: string | undefined = event?.type;
    if (!uid || !type) {
      res.status(400).send("Bad Request");
      return;
    }

    let active: boolean | undefined;
    if (ACTIVATING.has(type) || type === "CANCELLATION") active = true;
    else if (DEACTIVATING.has(type)) active = false;
    if (active === undefined) {
      res.status(200).send("Ignored"); // TEST, TRANSFER, etc.
      return;
    }

    const subscription: Record<string, unknown> = {
      active,
      productId: event?.product_id ?? null,
      store: event?.store ?? null,
      updatedAt: Timestamp.now(),
    };
    const expirationMs = event?.expiration_at_ms as number | undefined;
    if (expirationMs) subscription.expiresAt = Timestamp.fromMillis(expirationMs);

    await getFirestore().collection("users").doc(uid).set({ subscription }, { merge: true });
    logger.info("RevenueCat entitlement synced", { uid, type, active });
    res.status(200).send("OK");
  },
);

/**
 * Constant-time comparison of the Authorization header against the shared
 * secret. A plain `!==` short-circuits at the first differing byte, which leaks
 * the secret one byte at a time to anyone who can time the response — this
 * endpoint is public, so that's a real attack, not a theoretical one.
 */
function isAuthorized(header: string | undefined): boolean {
  const expected = REVENUECAT_WEBHOOK_AUTH.value();
  // An unset secret must authorize nothing at all.
  if (!expected || !header) return false;
  const sent = Buffer.from(header);
  const want = Buffer.from(expected);
  // timingSafeEqual throws on differing lengths; the length is not the secret.
  return sent.length === want.length && timingSafeEqual(sent, want);
}
