import { defineSecret } from "firebase-functions/params";

/**
 * Backend-only secrets. Set them with:
 *   firebase functions:secrets:set ELEVENLABS_API_KEY
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 * Never expose these to the Flutter client.
 */
export const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
export const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
/** Shared secret guarding the RevenueCat → entitlement-sync webhook. */
export const REVENUECAT_WEBHOOK_AUTH = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** Single deployment region for all functions. */
export const REGION = "us-central1";

/**
 * App Check enforcement for all callables. Flip to `true` ONLY after registering
 * debug tokens (Firebase console → App Check → Manage debug tokens) and enabling
 * App Attest / Play Integrity — otherwise every client call is rejected. See
 * SETUP.md (Phase 5 §D).
 */
export const ENFORCE_APP_CHECK = false;

/** Claude model used for kid-safe story generation (see SETUP.md). */
export const STORY_MODEL = "claude-sonnet-4-6";

/** Cheaper/faster Claude model for moderation + tag extraction (classification). */
export const MODERATION_MODEL = "claude-haiku-4-5";

/** ElevenLabs TTS model — multilingual v2 is their highest-quality narration model. */
export const TTS_MODEL = "eleven_multilingual_v2";

/** mp3 44.1kHz 128kbps — good quality, small enough for mobile streaming. */
export const TTS_OUTPUT_FORMAT = "mp3_44100_128" as const;

// --- Bedtime narration pacing -------------------------------------------
/** Speech rate: 1.0 is default, below 1.0 is slower and calmer. */
export const NARRATION_SPEED = 0.92;
/** Extra silence inserted after each sentence, in seconds. */
export const NARRATION_SENTENCE_PAUSE_SEC = 0.55;
/** Extra silence between paragraphs, in seconds. */
export const NARRATION_PARAGRAPH_PAUSE_SEC = 1.0;
/**
 * Bump when pacing settings change: cached narrations recorded with an older
 * value are re-synthesized instead of served stale.
 */
export const NARRATION_PACING_VERSION = 2;

/** A community story auto-hides (status → "under_review") at this many reports. */
export const REPORT_HIDE_THRESHOLD = 3;

// --- Plan limits ---------------------------------------------------------
/** Free-tier caps, lifted by an active subscription. */
export const FREE_MAX_VOICES = 1;
export const FREE_PLAYS_PER_WEEK = 2;
/** Abuse caps — apply to everyone (incl. subscribers) as a cost backstop. */
export const ABUSE_GENERATE_PER_DAY = 20;
export const ABUSE_NARRATE_PER_DAY = 100;
export const ABUSE_PUBLISH_PER_DAY = 10;
export const ABUSE_COMMENT_PER_HOUR = 60;
