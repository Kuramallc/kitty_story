import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import { onCall } from "firebase-functions/v2/https";

import { requireAuth } from "./auth";
import { ELEVENLABS_API_KEY, ENFORCE_APP_CHECK, REGION } from "./config";
import { elevenLabsClient } from "./elevenlabs";

/**
 * Right to erasure: removes everything tied to the signed-in account, then the
 * account itself.
 *
 * Required in-app by App Store guideline 5.1.1(v) and by Google Play — a
 * website request form satisfies neither, and our privacy policy promises this
 * outright.
 *
 * Deliberately gated on `requireAuth`, NOT `requireVerifiedEmail`: someone who
 * never verified their address must still be able to leave. Making the exit
 * harder than the entrance is exactly what the guideline is aimed at.
 *
 * Order matters. Everything external or recoverable goes first and the Firebase
 * Auth record goes last, so a failure part-way through leaves the user still
 * signed in and able to retry. Deleting auth first would strand them with
 * orphaned data and no way to reach it.
 */
export const deleteAccount = onCall(
  {
    region: REGION,
    secrets: [ELEVENLABS_API_KEY],
    timeoutSeconds: 540,
    memory: "512MiB",
    enforceAppCheck: ENFORCE_APP_CHECK,
  },
  async (request) => {
    const uid = requireAuth(request);
    const db = getFirestore();
    const bucket = getStorage().bucket();
    const userRef = db.collection("users").doc(uid);

    logger.info("Account deletion requested", { uid });

    // 1. Cloned voices at ElevenLabs. Third-party state we cannot reach again
    //    once the Firestore docs holding the ids are gone, so it goes first.
    const voices = await userRef.collection("voices").get();
    for (const doc of voices.docs) {
      const elevenLabsVoiceId = doc.get("elevenLabsVoiceId") as string | undefined;
      if (!elevenLabsVoiceId) continue;
      try {
        await elevenLabsClient().voices.delete(elevenLabsVoiceId);
      } catch (error) {
        // Already gone, or their API is down. Keep going: a stuck vendor must
        // not block the user's right to delete their account.
        logger.warn("ElevenLabs voice delete failed during account deletion", {
          uid, elevenLabsVoiceId,
          errorMessage: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // 2. Community stories this user published, with their likes/comments/reports.
    const published = await db
      .collection("publishedStories").where("authorUid", "==", uid).get();
    for (const doc of published.docs) {
      await db.recursiveDelete(doc.ref);
    }
    const ownStoryIds = new Set(published.docs.map((d) => d.id));

    // 3. Comments this user left on *other* people's stories, with the
    //    denormalized counter kept honest.
    const comments = await db
      .collectionGroup("comments").where("authorUid", "==", uid).get();
    for (const doc of comments.docs) {
      const storyRef = doc.ref.parent.parent;
      await doc.ref.delete();
      if (storyRef && !ownStoryIds.has(storyRef.id)) {
        await storyRef.update({ commentCount: FieldValue.increment(-1) })
          .catch(() => undefined); // story already gone
      }
    }

    // 4. Likes. These are keyed by uid rather than storing it as a field, so
    //    they cannot be found with a collection-group query — we check each
    //    story directly. Fine at this scale; revisit if publishedStories grows
    //    into the thousands.
    const allStories = await db.collection("publishedStories").select().get();
    for (const story of allStories.docs) {
      if (ownStoryIds.has(story.id)) continue; // already recursively deleted
      const likeRef = story.ref.collection("likes").doc(uid);
      if (!(await likeRef.get()).exists) continue;
      await likeRef.delete();
      await story.ref.update({ likeCount: FieldValue.increment(-1) })
        .catch(() => undefined);
    }

    // 5. Storage: voice samples and every synthesized narration.
    await bucket.deleteFiles({ prefix: `users/${uid}/` }).catch((error) => {
      logger.warn("Storage cleanup failed during account deletion", {
        uid, errorMessage: error instanceof Error ? error.message : String(error),
      });
    });

    // 6. The whole Firestore subtree: voices, generatedStories, narrations,
    //    limits, archived, and the user doc itself.
    await db.recursiveDelete(userRef);

    // 7. The auth record, last.
    await getAuth().deleteUser(uid);

    logger.info("Account deleted", {
      uid,
      voices: voices.size,
      publishedStories: published.size,
      comments: comments.size,
    });
    return { deleted: true };
  },
);
