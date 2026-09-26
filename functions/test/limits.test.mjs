/**
 * Quota tests for src/limits.ts, run against the Firestore emulator.
 *
 * These decide who gets a billable narration. ElevenLabs charges per
 * character, so an off-by-one here either gives synthesis away or turns away
 * someone who should have been served — and the welcome day makes the window
 * arithmetic non-obvious enough to be worth pinning down.
 *
 * Run: npm --prefix functions test
 */
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { FREE_PLAYS_PER_WEEK, WELCOME_DAY_PLAYS } from "../lib/config.js";
import { enforceQuota } from "../lib/limits.js";

initializeApp({ projectId: "demo-kitty-limits" });
const db = getFirestore();

const MINUTE = 60 * 1000;
const DAY = 24 * 60 * MINUTE;
const WEEK = 7 * DAY;

let seq = 0;
const nextUid = () => `quota-user-${Date.now()}-${seq++}`;

/** Plays until the quota refuses, returning how many got through and why it stopped. */
async function playUntilBlocked(uid, ceiling = 20) {
  for (let n = 0; n < ceiling; n++) {
    try {
      await enforceQuota(uid, "synthesizeNarration");
    } catch (error) {
      return { count: n, message: error.message };
    }
  }
  return { count: ceiling, message: null };
}

/** Rewinds a limit window's start, standing in for the passage of time. */
async function rewind(uid, key, ms) {
  const ref = db.doc(`users/${uid}/limits/${key}`);
  const startMs = (await ref.get()).get("windowStart").toMillis();
  await ref.update({ windowStart: Timestamp.fromMillis(startMs - ms) });
}

describe("narration quota", () => {
  test("the head start is bigger than the steady-state allowance", () => {
    // Otherwise every assertion below would pass for the wrong reason.
    assert.ok(WELCOME_DAY_PLAYS > FREE_PLAYS_PER_WEEK);
  });

  test("a new user gets WELCOME_DAY_PLAYS on their first day", async () => {
    const uid = nextUid();
    const first = await playUntilBlocked(uid);
    assert.equal(first.count, WELCOME_DAY_PLAYS);
    assert.match(first.message, /first day/);
  });

  test("running out on day one does not spend the week's plays", async () => {
    const uid = nextUid();
    await playUntilBlocked(uid); // exhaust the head start
    await rewind(uid, "synthesizeNarration_welcome", DAY + MINUTE);

    const afterward = await playUntilBlocked(uid);
    assert.equal(afterward.count, FREE_PLAYS_PER_WEEK);
    assert.match(afterward.message, /weekly limit/);
  });

  test("the head start is granted once, not every day", async () => {
    const uid = nextUid();
    await playUntilBlocked(uid);
    await rewind(uid, "synthesizeNarration_welcome", DAY + MINUTE);
    await playUntilBlocked(uid); // spend the first week

    // A week later the ordinary allowance renews — the head start does not.
    await rewind(uid, "synthesizeNarration_free", WEEK + MINUTE);
    const nextWeek = await playUntilBlocked(uid);
    assert.equal(nextWeek.count, FREE_PLAYS_PER_WEEK);
  });

  test("a subscriber is never charged a free-tier play", async () => {
    const uid = nextUid();
    await db.doc(`users/${uid}`).set({ subscription: { active: true } });
    const { count, message } = await playUntilBlocked(uid, WELCOME_DAY_PLAYS * 3);
    assert.equal(message, null);
    assert.equal(count, WELCOME_DAY_PLAYS * 3);
  });
});
