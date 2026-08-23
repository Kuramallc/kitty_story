/**
 * Security-rules tests for firestore.rules.
 *
 * These are the enforcement boundary for three exploits that were live before
 * this suite existed: forging a moderation verdict to publish unmoderated text
 * to other families' children, pointing your own voice doc at another family's
 * cloned ElevenLabs voice, and fabricating the ElevenLabs consent record.
 * Cloud Functions read those fields and trust them, so if a rule here regresses,
 * the backend has no second line of defence.
 *
 * Run: npm --prefix firestore-tests test
 */
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

const ALICE = "alice_uid";
const BOB = "bob_uid";
const VOICE = "voice_1";
const STORY = "story_1";
const PUBLISHED = "published_1";
const HIDDEN = "hidden_1";

let testEnv;
let alice;
let bob;

/** Exactly what VoiceRepository.createVoiceAndClone sends. */
function voicePayload(overrides = {}) {
  return {
    name: "Grandma",
    status: "pending",
    samplePath: `users/${ALICE}/voiceSamples/${VOICE}.m4a`,
    consent: {
      accepted: true,
      version: "2026-06.1",
      at: serverTimestamp(),
    },
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

const voiceDoc = (db, uid = ALICE, voiceId = VOICE) =>
  doc(db, "users", uid, "voices", voiceId);
const generatedDoc = (db, uid = ALICE, storyId = STORY) =>
  doc(db, "users", uid, "generatedStories", storyId);

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "kitty-story-rules-test",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  alice = testEnv.authenticatedContext(ALICE).firestore();
  bob = testEnv.authenticatedContext(BOB).firestore();

  // Seed the documents Cloud Functions own (Admin SDK bypasses rules).
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", ALICE, "voices", VOICE), {
      name: "Grandma",
      status: "ready",
      samplePath: `users/${ALICE}/voiceSamples/${VOICE}.m4a`,
      elevenLabsVoiceId: "el_alice_secret",
      consent: { accepted: true, version: "2026-06.1", at: new Date() },
      createdAt: new Date(),
    });
    await setDoc(doc(db, "users", ALICE, "generatedStories", STORY), {
      title: "The Sleepy Fox",
      text: "Once upon a time…",
      createdAt: new Date(),
    });
    await setDoc(doc(db, "publishedStories", PUBLISHED), {
      title: "A Gentle Night",
      text: "…",
      authorUid: BOB,
      status: "published",
      likeCount: 0,
      createdAt: new Date(),
    });
    await setDoc(doc(db, "publishedStories", HIDDEN), {
      title: "Auto-hidden",
      text: "…",
      authorUid: BOB,
      status: "under_review",
      likeCount: 0,
      reportCount: 3,
      createdAt: new Date(),
    });
  });
});

describe("generatedStories — the moderation-bypass hole", () => {
  test("denies forging a moderation verdict", async () => {
    // The exploit: publishStory reuses `moderation` when textSha matches, so a
    // writable field here publishes anything, unmoderated, to other kids.
    await assertFails(
      updateDoc(generatedDoc(alice), {
        moderation: { safe: true, textSha: "deadbeef", at: serverTimestamp() },
      }),
    );
  });

  test("denies any client create or update", async () => {
    await assertFails(
      setDoc(generatedDoc(alice, ALICE, "forged"), { title: "x", text: "y" }),
    );
    await assertFails(updateDoc(generatedDoc(alice), { text: "rewritten" }));
  });

  test("allows the owner to read and delete their own story", async () => {
    await assertSucceeds(getDoc(generatedDoc(alice)));
    await assertSucceeds(deleteDoc(generatedDoc(alice)));
  });

  test("denies another user reading it", async () => {
    await assertFails(getDoc(generatedDoc(bob, ALICE, STORY)));
  });
});

describe("voices — cross-family voice hijack and consent forgery", () => {
  test("allows the exact payload the app sends", async () => {
    await assertSucceeds(setDoc(voiceDoc(alice, ALICE, "new_voice"), voicePayload()));
  });

  test("denies claiming another family's cloned voice", async () => {
    // The exploit: synthesizeNarration reads elevenLabsVoiceId off this doc.
    await assertFails(
      updateDoc(voiceDoc(alice), { elevenLabsVoiceId: "el_someone_elses" }),
    );
    await assertFails(
      setDoc(
        voiceDoc(alice, ALICE, "hijack"),
        voicePayload({ elevenLabsVoiceId: "el_someone_elses" }),
      ),
    );
  });

  test("denies self-promoting a voice to ready", async () => {
    await assertFails(updateDoc(voiceDoc(alice), { status: "processing" }));
    await assertFails(
      setDoc(voiceDoc(alice, ALICE, "instant"), voicePayload({ status: "ready" })),
    );
  });

  test("denies forged or backdated consent", async () => {
    await assertFails(
      setDoc(
        voiceDoc(alice, ALICE, "no_consent"),
        voicePayload({ consent: { accepted: false, version: "2026-06.1", at: serverTimestamp() } }),
      ),
    );
    // A client-chosen timestamp: consent must be stamped by the server.
    await assertFails(
      setDoc(
        voiceDoc(alice, ALICE, "backdated"),
        voicePayload({
          consent: { accepted: true, version: "2026-06.1", at: new Date(0) },
        }),
      ),
    );
  });

  test("denies pointing at another user's sample", async () => {
    await assertFails(
      setDoc(
        voiceDoc(alice, ALICE, "foreign_sample"),
        voicePayload({ samplePath: `users/${BOB}/voiceSamples/x.m4a` }),
      ),
    );
  });

  test("allows a rename, nothing else", async () => {
    await assertSucceeds(updateDoc(voiceDoc(alice), { name: "Grandpa" }));
    // The seed is already status "ready", so smuggle in a value that actually
    // differs — affectedKeys() (rightly) ignores writes that change nothing.
    await assertFails(
      updateDoc(voiceDoc(alice), { name: "Nana", status: "pending" }),
    );
  });

  test("denies deleting the doc directly (orphans the ElevenLabs voice)", async () => {
    await assertFails(deleteDoc(voiceDoc(alice)));
  });

  test("denies touching another user's voices", async () => {
    await assertFails(getDoc(voiceDoc(bob, ALICE, VOICE)));
    await assertFails(updateDoc(voiceDoc(bob, ALICE, VOICE), { name: "mine now" }));
  });
});

describe("users — subscription entitlement", () => {
  test("denies granting yourself a subscription", async () => {
    await assertFails(
      setDoc(doc(alice, "users", ALICE), { subscription: { active: true } }),
    );
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", ALICE), { displayName: "Alice" });
    });
    await assertFails(
      updateDoc(doc(alice, "users", ALICE), { subscription: { active: true } }),
    );
  });

  test("denies writing quota counters", async () => {
    await assertFails(
      setDoc(doc(alice, "users", ALICE, "limits", "synthesizeNarration_free"), {
        count: 0,
        windowStart: serverTimestamp(),
      }),
    );
  });
});

describe("publishedStories — hidden content stays hidden", () => {
  test("allows reading a published story", async () => {
    await assertSucceeds(getDoc(doc(alice, "publishedStories", PUBLISHED)));
  });

  test("denies reading an auto-hidden story by id", async () => {
    await assertFails(getDoc(doc(alice, "publishedStories", HIDDEN)));
  });

  test("allows the Explore query, which filters on status", async () => {
    await assertSucceeds(
      getDocs(
        query(collection(alice, "publishedStories"), where("status", "==", "published")),
      ),
    );
  });

  test("denies an unfiltered listing", async () => {
    await assertFails(getDocs(collection(alice, "publishedStories")));
  });

  test("denies signed-out reads and all client writes", async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "publishedStories", PUBLISHED)));
    await assertFails(
      updateDoc(doc(alice, "publishedStories", PUBLISHED), { likeCount: 999 }),
    );
  });
});

describe("reports — one per user, so three can't hide anyone's story", () => {
  const report = (db, storyId, reportId, data = {}) =>
    setDoc(doc(db, "publishedStories", storyId, "reports", reportId), {
      reporterUid: data.reporterUid ?? (db === alice ? ALICE : BOB),
      reason: data.reason ?? "Not appropriate for kids",
      at: serverTimestamp(),
      ...data,
    });

  test("allows one report, at the reporter's own uid", async () => {
    await assertSucceeds(report(alice, PUBLISHED, ALICE));
  });

  test("denies a second report from the same user", async () => {
    await assertSucceeds(report(alice, PUBLISHED, ALICE));
    // The exploit: three of these auto-hid any story (REPORT_HIDE_THRESHOLD).
    await assertFails(report(alice, PUBLISHED, ALICE));
  });

  test("denies reports filed under any other id", async () => {
    await assertFails(report(alice, PUBLISHED, "extra_report_1"));
    await assertFails(report(alice, PUBLISHED, BOB, { reporterUid: BOB }));
  });

  test("denies a mismatched reporterUid or an oversized reason", async () => {
    await assertFails(report(alice, PUBLISHED, ALICE, { reporterUid: BOB }));
    await assertFails(report(alice, PUBLISHED, ALICE, { reason: "x".repeat(301) }));
  });

  test("denies reading other people's reports", async () => {
    await assertSucceeds(report(alice, PUBLISHED, ALICE));
    await assertFails(getDoc(doc(alice, "publishedStories", PUBLISHED, "reports", ALICE)));
  });
});
