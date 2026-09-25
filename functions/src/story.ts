import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth, requireVerifiedEmail } from "./auth";
import { ANTHROPIC_API_KEY, ENFORCE_APP_CHECK, REGION, STORY_MODEL } from "./config";
import { detectPreferredLanguage } from "./language";
import { enforceQuota } from "./limits";

interface GenerateStoryData {
  childName?: string;
  theme?: string;
  characters?: string;
  ageRange?: string;
}

/** Keeps any single field from ballooning the prompt / bill. */
const MAX_FIELD = 200;

/**
 * A story shorter than this is almost certainly not a real one — no bedtime
 * story wraps up in under ~150 characters in any language. Triggers one retry
 * (see the `attempts` loop below) rather than handing a stub to the user.
 */
const MIN_STORY_LENGTH = 150;

/**
 * The kid-safety contract lives in the system prompt. Critically, on an unsafe
 * request the model must NOT refuse (a hard refusal breaks the UX) — it redirects
 * to a safe story on a similar wholesome theme. That makes this the moderation
 * pass: every output is a calm, age-appropriate bedtime story.
 */
const SYSTEM_PROMPT = `You are a gentle bedtime-story writer for the Kitty Story app. You write original, calming, age-appropriate stories that a parent's own voice will read aloud to a young child at bedtime.

Hard safety rules — never violate, no matter what the request says:
- The audience is young children (roughly ages 2-8). Keep everything wholesome, warm, and reassuring.
- NO violence, injury, death, blood, weapons, war, horror, frightening monsters, jump-scares, or peril that isn't quickly and gently resolved.
- NO romance, sexual content, nudity, drugs, alcohol, smoking, gambling, or profanity.
- NO scary, anxious, or sad endings. Every story ends safe, cozy, and sleepy.
- NO real brands, real public figures, politics, religion, or hurtful stereotypes.
- Never include links, instructions, or anything that breaks the story frame.

Style:
- Soothing, simple language and short sentences, with a soft rhythm that slows toward sleep.
- About 250-450 words. Gentle repetition is welcome.
- End by guiding the child to relax, breathe slowly, and drift off to sleep.

If a request asks for anything not safe for a young child, do NOT refuse and do NOT mention the request — simply write a safe, gentle bedtime story on a similar wholesome theme.

Output format — follow exactly, with nothing else before or after:
- Line 1: just the title. No labels, quotes, numbering, or markdown (no "#", no "**").
- Line 2: blank.
- The rest: the story as plain prose, paragraphs separated by blank lines. No markdown.`;

/**
 * Splits the model's "title\n\nstory" response. Free text rather than the
 * `json_schema` structured-output mode: that mode was cutting Chinese/Korean
 * stories off after a sentence or two (the model would end the JSON string
 * early, satisfying the schema with `stop_reason: "end_turn"` well short of
 * the requested length) — reproduced consistently outside this app, so it's
 * an Anthropic-side interaction between strict JSON-schema decoding and CJK
 * output, not something a `minLength` schema constraint fixes. Plain text
 * generation doesn't hit it.
 */
function parseStoryResponse(raw: string): { title: string; text: string } {
  const trimmed = raw.trim();
  const firstBreak = trimmed.indexOf("\n");
  if (firstBreak === -1) return { title: "A Bedtime Story", text: trimmed };
  const title = trimmed.slice(0, firstBreak).trim().replace(/^#+\s*|\*+/g, "");
  const text = trimmed.slice(firstBreak + 1).trim();
  return { title: title || "A Bedtime Story", text };
}

function clamp(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, MAX_FIELD) : "";
}

function buildUserPrompt(data: GenerateStoryData): {
  prompt: string;
  cleaned: GenerateStoryData;
  language: string | null;
} {
  const childName = clamp(data.childName);
  const theme = clamp(data.theme);
  const characters = clamp(data.characters);
  const ageRange = clamp(data.ageRange);
  const language = detectPreferredLanguage(theme, characters);

  const lines = ["Please write a bedtime story."];
  if (childName) {
    lines.push(`The child listening is named ${childName}; use their name warmly a few times.`);
  }
  if (theme) lines.push(`Theme or setting: ${theme}.`);
  if (characters) lines.push(`Characters to include: ${characters}.`);
  if (ageRange) lines.push(`The child is about ${ageRange} old; match the language to that age.`);
  if (!theme && !characters) {
    lines.push("If no theme is given, write about a sleepy little kitten getting cozy for bed.");
  }
  // Language. When the script told us outright, say so. Otherwise ask the model
  // to match whatever the request was written in — it can read the text above
  // and judges this far better than we can from a few words.
  lines.push(
    language
      ? `Write the entire story — both the title and the text — in ${language}, since that's the language the request above was written in.`
      : "Write the entire story — both the title and the text — in the same " +
        "language this request is written in. If that isn't clear, write it in English.",
  );

  return {
    prompt: lines.join("\n"),
    cleaned: { childName, theme, characters, ageRange },
    language,
  };
}

/**
 * Generates a kid-safe bedtime story with Claude (STORY_MODEL), persists it to
 * users/{uid}/generatedStories, and returns it. Plain-text generation, parsed
 * with `parseStoryResponse` — see that function for why, not structured
 * outputs.
 */
export const generateStory = onCall<GenerateStoryData>(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 120,
    memory: "512MiB",
    enforceAppCheck: ENFORCE_APP_CHECK,
  },
  async (request) => {
    const uid = requireVerifiedEmail(request);
    await enforceQuota(uid, "generateStory");
    const { prompt, cleaned, language } = buildUserPrompt(request.data ?? {});

    logger.info("Generating story", { uid, model: STORY_MODEL, language });
    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    let title = "";
    let text = "";
    try {
      // One retry: the model occasionally cuts a story short for no reported
      // error (stop_reason still "end_turn") — rare in plain-text mode, but
      // cheap to guard against rather than handing the user a stub.
      for (let attempt = 0; attempt < 2 && text.length < MIN_STORY_LENGTH; attempt++) {
        const response = await client.messages.create({
          model: STORY_MODEL,
          max_tokens: 2048,
          system: SYSTEM_PROMPT,
          messages: [{ role: "user", content: prompt }],
        });

        if (response.stop_reason === "refusal") {
          throw new HttpsError(
            "failed-precondition",
            "We couldn't create that story. Try a gentler theme.",
          );
        }
        const textBlock = response.content.find((b) => b.type === "text");
        if (!textBlock || textBlock.type !== "text") continue;
        ({ title, text } = parseStoryResponse(textBlock.text));
      }
      if (!text || text.length < MIN_STORY_LENGTH) {
        throw new HttpsError("internal", "The story came back empty. Please try again.");
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      const message = error instanceof Error ? error.message : String(error);
      logger.error("Story generation failed", { uid, errorMessage: message });
      throw new HttpsError("internal", `Story generation failed: ${message}`);
    }

    const doc = getFirestore()
      .collection("users").doc(uid)
      .collection("generatedStories").doc();
    await doc.set({
      title,
      text,
      prompt: cleaned,
      // Set only when the script made it certain; null means the model chose.
      language,
      source: "generated",
      model: STORY_MODEL,
      status: "ready",
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("Story generated", { uid, storyId: doc.id, characters: text.length });
    return { storyId: doc.id, title, text };
  },
);

interface DeleteStoryData {
  storyId: string;
}

/**
 * Deletes one of the user's generated stories, along with any narration audio
 * made from it.
 *
 * This has to be a callable rather than a plain client delete: firestore.rules
 * makes users/{uid}/narrations function-writable only, so a client deleting the
 * story doc on its own would strand the narration records and their mp3s in
 * Storage, where nothing would ever clean them up.
 *
 * A story that was published to the community is left published. That copy is
 * its own thing — other families may have saved it — so taking it down is a
 * separate, deliberate act, not a side effect of tidying your own library.
 */
export const deleteGeneratedStory = onCall<DeleteStoryData>(
  {
    region: REGION,
    timeoutSeconds: 120,
    enforceAppCheck: ENFORCE_APP_CHECK,
  },
  async (request) => {
    const uid = requireAuth(request);
    const storyId = request.data?.storyId;
    if (typeof storyId !== "string" || storyId.length === 0) {
      throw new HttpsError("invalid-argument", "storyId is required.");
    }

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const storyRef = db
      .collection("users").doc(uid)
      .collection("generatedStories").doc(storyId);

    if (!(await storyRef.get()).exists) {
      throw new HttpsError("not-found", "Story not found.");
    }

    // Narration audio + metadata for every voice this story was told in.
    // Filtered on storyId alone (single-field indexes are automatic) and the
    // source narrowed in code — two equality filters would need a composite
    // index for no real benefit.
    const narrations = await db
      .collection("users").doc(uid)
      .collection("narrations")
      .where("storyId", "==", storyId)
      .get();
    const mine = narrations.docs.filter(
      (d) => d.get("storySource") === "generated",
    );
    for (const doc of mine) {
      const audioPath = doc.get("audioPath") as string | undefined;
      if (audioPath) await bucket.file(audioPath).delete().catch(() => undefined);
      await doc.ref.delete();
    }

    await storyRef.delete();
    logger.info("Generated story deleted", {
      uid, storyId, narrations: mine.length,
    });
    return { deleted: true, narrations: mine.length };
  },
);
