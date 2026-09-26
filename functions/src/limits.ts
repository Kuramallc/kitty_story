import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import {
  ABUSE_COMMENT_PER_HOUR,
  ABUSE_GENERATE_PER_DAY,
  ABUSE_NARRATE_PER_DAY,
  ABUSE_PUBLISH_PER_DAY,
  FREE_MAX_VOICES,
  FREE_PLAYS_PER_WEEK,
  WELCOME_DAY_PLAYS,
} from "./config";

const HOUR = 60 * 60;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;

const UPGRADE_MSG =
  "You've reached the free plan's weekly limit. Upgrade for unlimited stories.";
const WELCOME_DONE_MSG =
  `That's ${WELCOME_DAY_PLAYS} stories on your first day. From here the free ` +
  `plan includes ${FREE_PLAYS_PER_WEEK} a week — upgrade for unlimited stories.`;
const SLOW_DOWN_MSG = "You're going a little fast — please try again in a bit.";

/** True if the user currently has an active, non-expired subscription. */
export async function isSubscribed(uid: string): Promise<boolean> {
  const snap = await getFirestore().collection("users").doc(uid).get();
  const sub = snap.get("subscription") as
    | { active?: boolean; expiresAt?: Timestamp }
    | undefined;
  if (sub?.active !== true) return false;
  const expMs = sub.expiresAt?.toMillis?.() ?? 0;
  return expMs === 0 || expMs > Date.now(); // no expiry recorded ⇒ trust the flag
}

interface Window {
  max: number;
  windowSec: number;
}
interface Rule {
  welcome?: Window; // a one-off head start, granted once and never renewed
  free?: Window; // lifted by an active subscription
  abuse?: Window; // applies to everyone
}

const RULES = {
  generateStory: { abuse: { max: ABUSE_GENERATE_PER_DAY, windowSec: DAY } },
  synthesizeNarration: {
    welcome: { max: WELCOME_DAY_PLAYS, windowSec: DAY },
    free: { max: FREE_PLAYS_PER_WEEK, windowSec: WEEK },
    abuse: { max: ABUSE_NARRATE_PER_DAY, windowSec: DAY },
  },
  publishStory: { abuse: { max: ABUSE_PUBLISH_PER_DAY, windowSec: DAY } },
  addComment: { abuse: { max: ABUSE_COMMENT_PER_HOUR, windowSec: HOUR } },
} satisfies Record<string, Rule>;

export type QuotaAction = keyof typeof RULES;

/**
 * Enforces the rolling-window quota(s) for an action and consumes one slot.
 * Free-tier limits are skipped for active subscribers; abuse limits apply to
 * everyone. Throws `resource-exhausted` (upgrade-friendly message) when a limit
 * is hit. Call once per *billable* attempt (e.g. a narration cache miss).
 */
export async function enforceQuota(uid: string, action: QuotaAction): Promise<void> {
  const rule: Rule = RULES[action];
  if (rule.free && !(await isSubscribed(uid))) {
    // The welcome window is spent first, so the first day never eats into the
    // weekly allowance — the week starts fresh once the head start lapses.
    const usedWelcome = rule.welcome
      ? await consumeWelcome(uid, `${action}_welcome`, rule.welcome)
      : false;
    if (!usedWelcome) {
      await consume(uid, `${action}_free`, rule.free, UPGRADE_MSG);
    }
  }
  if (rule.abuse) {
    await consume(uid, `${action}_abuse`, rule.abuse, SLOW_DOWN_MSG);
  }
}

/**
 * Free tier caps the number of voice profiles. Throws `resource-exhausted` when
 * a non-subscriber already has FREE_MAX_VOICES voices other than the one being
 * created.
 */
export async function enforceVoiceLimit(uid: string, currentVoiceId: string): Promise<void> {
  if (await isSubscribed(uid)) return;
  const voices = await getFirestore()
    .collection("users").doc(uid).collection("voices").get();
  const others = voices.docs.filter((d) => d.id !== currentVoiceId).length;
  if (others >= FREE_MAX_VOICES) {
    throw new HttpsError(
      "resource-exhausted",
      `The free plan includes ${FREE_MAX_VOICES} ${FREE_MAX_VOICES === 1 ? "voice" : "voices"}. Upgrade for unlimited voices.`,
    );
  }
}

/**
 * A one-off head start covering a user's first [w.windowSec] of an action.
 *
 * Unlike [consume] this window never renews: the counter opens on the first
 * call and, once it lapses, is left alone forever so the head start cannot be
 * claimed twice.
 *
 * Returns true when a welcome slot was consumed, false when the window has
 * already lapsed and the caller should fall through to the ordinary allowance.
 * Throws `resource-exhausted` while still inside the window with nothing left,
 * rather than falling through — otherwise a busy first night would quietly
 * spend the week's plays too.
 */
async function consumeWelcome(uid: string, key: string, w: Window): Promise<boolean> {
  const ref = getFirestore()
    .collection("users").doc(uid).collection("limits").doc(key);
  return getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.set(ref, { count: 1, windowStart: FieldValue.serverTimestamp() });
      return true;
    }
    // A missing windowStart reads as 0, which lapses immediately — degrading to
    // the ordinary weekly allowance rather than handing out a fresh head start.
    const startMs = (snap.get("windowStart") as Timestamp | undefined)?.toMillis?.() ?? 0;
    if (Date.now() - startMs >= w.windowSec * 1000) return false;
    const count = (snap.get("count") as number | undefined) ?? 0;
    if (count >= w.max) {
      throw new HttpsError("resource-exhausted", WELCOME_DONE_MSG);
    }
    tx.update(ref, { count: count + 1 });
    return true;
  });
}

/** Atomic rolling-window counter at users/{uid}/limits/{key}. */
async function consume(uid: string, key: string, w: Window, msg: string): Promise<void> {
  const ref = getFirestore()
    .collection("users").doc(uid).collection("limits").doc(key);
  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const startMs = (snap.get("windowStart") as Timestamp | undefined)?.toMillis?.() ?? 0;
    const count = (snap.get("count") as number | undefined) ?? 0;
    if (!snap.exists || now - startMs >= w.windowSec * 1000) {
      tx.set(ref, { count: 1, windowStart: FieldValue.serverTimestamp() });
      return;
    }
    if (count >= w.max) {
      throw new HttpsError("resource-exhausted", msg);
    }
    tx.update(ref, { count: count + 1 });
  });
}
