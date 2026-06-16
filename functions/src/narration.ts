import { randomUUID } from "node:crypto";

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "./auth";
import {
  ELEVENLABS_API_KEY,
  REGION,
  TTS_MODEL,
  TTS_OUTPUT_FORMAT,
} from "./config";
import { elevenLabsClient, streamToBuffer } from "./elevenlabs";

type StorySource = "library" | "generated" | "test" | "published";

interface SynthesizeNarrationData {
  storyId: string;
  storySource: StorySource;
  voiceId: string;
}

/** Short, kid-friendly sample used by the "Test this voice" button (Phase 2). */
const TEST_STORY_TEXT =
  "Once upon a time, a little kitten named Luna curled up under the stars. " +
  "“Goodnight, moon,” she whispered. " +
  "“Goodnight, little one. Sweet dreams.”";

/**
 * Synthesizes a story in a cloned voice — idempotent and cached.
 *
 * Cache key: {storySource}_{storyId}_{voiceId}. If that narration doc already
 * exists with audio, we return its URL without calling ElevenLabs again
 * (TTS bills per character; never pay for the same audio twice).
 */
export const synthesizeNarration = onCall<SynthesizeNarrationData>(
  {
    region: REGION,
    secrets: [ELEVENLABS_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
    // TODO(Phase 5): re-enable App Check enforcement for release.
    enforceAppCheck: false,
  },
  async (request) => {
    const uid = requireAuth(request);
    const { storyId, storySource, voiceId } = request.data ?? {};
    if (
      typeof storyId !== "string" || storyId.length === 0 ||
      typeof voiceId !== "string" || voiceId.length === 0 ||
      !["library", "generated", "test", "published"].includes(storySource as string)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "storyId, storySource (library|generated|test|published) and voiceId are required.",
      );
    }

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const narrationId = `${storySource}_${storyId}_${voiceId}`;
    const narrationRef = db
      .collection("users").doc(uid)
      .collection("narrations").doc(narrationId);

    // Serve from cache when we already synthesized this (story, voice) pair.
    const cached = await narrationRef.get();
    if (cached.exists && cached.get("status") === "ready") {
      return {
        narrationId,
        url: tokenUrl(bucket.name, cached.get("audioPath"), cached.get("downloadToken")),
        cached: true,
      };
    }

    const text = await resolveStoryText(uid, storyId, storySource as StorySource);

    const voiceSnapshot = await db
      .collection("users").doc(uid)
      .collection("voices").doc(voiceId).get();
    const elevenLabsVoiceId = voiceSnapshot.get("elevenLabsVoiceId") as string | undefined;
    if (!voiceSnapshot.exists || !elevenLabsVoiceId || voiceSnapshot.get("status") !== "ready") {
      throw new HttpsError("failed-precondition", "Voice is not ready for narration.");
    }

    logger.info("Synthesizing narration", {
      uid, narrationId, characters: text.length,
    });
    const stream = await elevenLabsClient().textToSpeech.convert(elevenLabsVoiceId, {
      text,
      modelId: TTS_MODEL,
      outputFormat: TTS_OUTPUT_FORMAT,
    });
    const audio = await streamToBuffer(stream);

    // Upload with a Firebase download token so the URL is stable and replays
    // are free (no signed-URL IAM requirements in v2 functions).
    const audioPath = `users/${uid}/narrations/${narrationId}.mp3`;
    const downloadToken = randomUUID();
    await bucket.file(audioPath).save(audio, {
      contentType: "audio/mpeg",
      metadata: { metadata: { firebaseStorageDownloadTokens: downloadToken } },
    });

    await narrationRef.set({
      storyId,
      storySource,
      voiceId,
      audioPath,
      downloadToken,
      characterCount: text.length,
      sizeBytes: audio.length,
      status: "ready",
      createdAt: FieldValue.serverTimestamp(),
    });

    return { narrationId, url: tokenUrl(bucket.name, audioPath, downloadToken), cached: false };
  },
);

/** Loads the story text for the given source, verifying it exists. */
async function resolveStoryText(
  uid: string,
  storyId: string,
  source: StorySource,
): Promise<string> {
  if (source === "test") return TEST_STORY_TEXT;

  const db = getFirestore();
  const ref = source === "library"
    ? db.collection("stories").doc(storyId)
    : source === "published"
      ? db.collection("publishedStories").doc(storyId)
      : db.collection("users").doc(uid).collection("generatedStories").doc(storyId);
  const snapshot = await ref.get();
  const text = snapshot.get("text") as string | undefined;
  if (!snapshot.exists || !text) {
    throw new HttpsError("not-found", `Story ${storyId} (${source}) has no text.`);
  }
  return text;
}

/** Public download URL backed by a firebaseStorageDownloadTokens token. */
function tokenUrl(bucketName: string, path: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}`;
}
