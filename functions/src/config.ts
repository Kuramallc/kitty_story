import { defineSecret } from "firebase-functions/params";

/**
 * Backend-only secrets. Set them with:
 *   firebase functions:secrets:set ELEVENLABS_API_KEY
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 * Never expose these to the Flutter client.
 */
export const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
// Note: ANTHROPIC_API_KEY is declared inside story.ts — defineSecret()
// registers the param at module load, so it must stay out of any module
// imported by index.ts until the secret exists (Phase 3).

/** Single deployment region for all functions. */
export const REGION = "us-central1";

/** Claude model used for kid-safe story generation (see SETUP.md). */
export const STORY_MODEL = "claude-sonnet-4-6";

/** ElevenLabs TTS model — multilingual v2 is their highest-quality narration model. */
export const TTS_MODEL = "eleven_multilingual_v2";

/** mp3 44.1kHz 128kbps — good quality, small enough for mobile streaming. */
export const TTS_OUTPUT_FORMAT = "mp3_44100_128" as const;
