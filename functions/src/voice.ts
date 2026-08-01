import { createReadStream } from "node:fs";
import { unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "./auth";
import { ELEVENLABS_API_KEY, ENFORCE_APP_CHECK, REGION } from "./config";
import { elevenLabsClient } from "./elevenlabs";
import { enforceVoiceLimit } from "./limits";

interface CreateVoiceProfileData {
  voiceId: string; // Firestore doc id under users/{uid}/voices
}

/**
 * Clones the uploaded voice sample with ElevenLabs Instant Voice Cloning.
 *
 * Preconditions (created client-side): users/{uid}/voices/{voiceId} exists,
 * consent.accepted == true, and the sample was uploaded to samplePath.
 * Writes back elevenLabsVoiceId + status "ready" (or "failed").
 */
export const createVoiceProfile = onCall<CreateVoiceProfileData>(
  {
    region: REGION,
    secrets: [ELEVENLABS_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
    enforceAppCheck: ENFORCE_APP_CHECK,
  },
  async (request) => {
    const uid = requireAuth(request);
    const voiceId = request.data?.voiceId;
    if (typeof voiceId !== "string" || voiceId.length === 0) {
      throw new HttpsError("invalid-argument", "voiceId is required.");
    }

    const voiceRef = getFirestore()
      .collection("users").doc(uid)
      .collection("voices").doc(voiceId);
    const snapshot = await voiceRef.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Voice profile not found.");
    }
    const voice = snapshot.data()!;
    if (voice.consent?.accepted !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Voice cloning requires recorded consent.",
      );
    }
    const samplePath = voice.samplePath as string | undefined;
    if (!samplePath || !samplePath.startsWith(`users/${uid}/voiceSamples/`)) {
      throw new HttpsError("failed-precondition", "No uploaded voice sample.");
    }
    if (voice.elevenLabsVoiceId) {
      return { elevenLabsVoiceId: voice.elevenLabsVoiceId, alreadyCloned: true };
    }

    // Free tier caps the number of voices (defense-in-depth — the client also
    // gates this before recording).
    await enforceVoiceLimit(uid, voiceId);

    await voiceRef.update({ status: "processing", error: FieldValue.delete() });

    const localPath = join(tmpdir(), `${uid}_${voiceId}.m4a`);
    try {
      const [bytes] = await getStorage().bucket().file(samplePath).download();
      await writeFile(localPath, bytes);

      const result = await elevenLabsClient().voices.ivc.create({
        name: `kitty_${uid.slice(0, 10)}_${voiceId.slice(0, 10)}`,
        files: [createReadStream(localPath)],
        description: "Kitty Story caregiver voice (consent recorded in-app)",
      });

      await voiceRef.update({
        elevenLabsVoiceId: result.voiceId,
        requiresVerification: result.requiresVerification,
        status: "ready",
        readyAt: FieldValue.serverTimestamp(),
      });
      logger.info("Voice cloned", { uid, voiceId, elevenLabsVoiceId: result.voiceId });
      return { elevenLabsVoiceId: result.voiceId, alreadyCloned: false };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // Field must not be named "message" — it collides with the log entry's
      // own message key and gets swallowed in Cloud Logging.
      logger.error("Voice cloning failed", { uid, voiceId, errorMessage: message });
      await voiceRef.update({ status: "failed", error: message });
      throw new HttpsError("internal", `Voice cloning failed: ${message}`);
    } finally {
      await unlink(localPath).catch(() => undefined);
    }
  },
);

interface DeleteVoiceProfileData {
  voiceId: string;
}

/**
 * Right-to-delete: removes the ElevenLabs voice, the Storage sample, all
 * narrations made with this voice (audio + docs), then the voice doc itself.
 */
export const deleteVoiceProfile = onCall<DeleteVoiceProfileData>(
  {
    region: REGION,
    secrets: [ELEVENLABS_API_KEY],
    timeoutSeconds: 120,
    enforceAppCheck: ENFORCE_APP_CHECK,
  },
  async (request) => {
    const uid = requireAuth(request);
    const voiceId = request.data?.voiceId;
    if (typeof voiceId !== "string" || voiceId.length === 0) {
      throw new HttpsError("invalid-argument", "voiceId is required.");
    }

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const voiceRef = db
      .collection("users").doc(uid)
      .collection("voices").doc(voiceId);
    const voice = (await voiceRef.get()).data();

    // 1. ElevenLabs voice (ignore if already gone).
    const elevenLabsVoiceId = voice?.elevenLabsVoiceId as string | undefined;
    if (elevenLabsVoiceId) {
      try {
        await elevenLabsClient().voices.delete(elevenLabsVoiceId);
      } catch (error) {
        logger.warn("ElevenLabs voice delete failed (continuing)", {
          uid, voiceId, elevenLabsVoiceId,
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // 2. Storage: raw sample(s) for this voice.
    await bucket.deleteFiles({
      prefix: `users/${uid}/voiceSamples/${voiceId}`,
    }).catch(() => undefined);

    // 3. Narrations that used this voice: audio files + metadata docs.
    const narrations = await db
      .collection("users").doc(uid)
      .collection("narrations")
      .where("voiceId", "==", voiceId)
      .get();
    for (const doc of narrations.docs) {
      const audioPath = doc.get("audioPath") as string | undefined;
      if (audioPath) await bucket.file(audioPath).delete().catch(() => undefined);
      await doc.ref.delete();
    }

    // 4. The voice doc itself.
    await voiceRef.delete();
    logger.info("Voice profile deleted", { uid, voiceId });
    return { deleted: true };
  },
);
