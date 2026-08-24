import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import LanguageDetect from "languagedetect";

import { requireVerifiedEmail } from "./auth";
import { ANTHROPIC_API_KEY, ENFORCE_APP_CHECK, REGION, STORY_MODEL } from "./config";
import { enforceQuota } from "./limits";

interface GenerateStoryData {
  childName?: string;
  theme?: string;
  characters?: string;
  ageRange?: string;
}

/** Keeps any single field from ballooning the prompt / bill. */
const MAX_FIELD = 200;

/** Guaranteed-valid shape for the model's response (structured outputs). */
const STORY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string", description: "A short, gentle title (3-6 words)." },
    text: {
      type: "string",
      description:
        "The full bedtime story as plain prose; paragraphs separated by blank lines.",
    },
  },
  required: ["title", "text"],
};

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

If a request asks for anything not safe for a young child, do NOT refuse and do NOT mention the request — simply write a safe, gentle bedtime story on a similar wholesome theme.`;

function clamp(value: unknown): string {
  return typeof value === "string" ? value.trim().slice(0, MAX_FIELD) : "";
}

const languageDetector = new LanguageDetect();

/**
 * Below this many characters of combined free text, language detection is
 * unreliable (a single name can score higher for Tagalog than English) — skip
 * it and fall through to the model's default.
 */
const MIN_DETECTION_CHARS = 8;
/** languagedetect's own confidence score for its top guess; below this, don't trust it. */
const MIN_DETECTION_CONFIDENCE = 0.1;

/**
 * Non-Latin scripts are unambiguous by Unicode block, which is far more
 * reliable on short prompt text than `languagedetect`'s n-gram model — that
 * package only knows Latin/Cyrillic-alphabet languages and returns nothing
 * useful for e.g. Chinese or Arabic. Checked in order, first match wins:
 * Japanese before Chinese since Japanese text almost always mixes in kana
 * even when it's mostly kanji, and Ukrainian-only Cyrillic letters before
 * plain Cyrillic (which defaults to Russian, the most common case).
 */
const SCRIPT_LANGUAGES: [RegExp, string][] = [
  [/\p{Script=Hiragana}|\p{Script=Katakana}/u, "Japanese"],
  [/\p{Script=Han}/u, "Chinese"],
  [/\p{Script=Hangul}/u, "Korean"],
  [/\p{Script=Arabic}/u, "Arabic"],
  [/\p{Script=Hebrew}/u, "Hebrew"],
  [/\p{Script=Devanagari}/u, "Hindi"],
  [/\p{Script=Bengali}/u, "Bengali"],
  [/\p{Script=Thai}/u, "Thai"],
  [/\p{Script=Greek}/u, "Greek"],
  [/[іїєґ]/i, "Ukrainian"],
  [/\p{Script=Cyrillic}/u, "Russian"],
  [/[đơư]|[ạảãầấẩẫậằắẳẵặẹẻẽềếệểễịỉĩọỏõồốộổỗờớợởỡụủũừứựửữỳỷỹ]/i, "Vietnamese"],
];

/**
 * Detects the dominant language of the user's free-text request (theme +
 * characters — childName is a proper noun and carries no language signal, so
 * it's excluded to avoid skewing the result) and returns its English name
 * (e.g. "Spanish"), or null if there isn't enough text to tell.
 */
function detectPreferredLanguage(theme: string, characters: string): string | null {
  const text = [theme, characters].filter(Boolean).join(". ");
  if (text.length < MIN_DETECTION_CHARS) return null;
  for (const [pattern, name] of SCRIPT_LANGUAGES) {
    if (pattern.test(text)) return name;
  }
  const [top] = languageDetector.detect(text, 1);
  if (!top || top[1] < MIN_DETECTION_CONFIDENCE) return null;
  const [name] = top;
  return name.charAt(0).toUpperCase() + name.slice(1);
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
  // The user's preferred language, inferred from what they typed above — write
  // the whole story in it rather than defaulting to English.
  if (language) {
    lines.push(`Write the entire story — both the title and the text — in ${language}, since that's the language the request above was written in.`);
  }

  return {
    prompt: lines.join("\n"),
    cleaned: { childName, theme, characters, ageRange },
    language,
  };
}

/**
 * Generates a kid-safe bedtime story with Claude (STORY_MODEL), persists it to
 * users/{uid}/generatedStories, and returns it. Uses structured outputs so the
 * response is always valid `{title, text}` JSON.
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

    let title: string;
    let text: string;
    try {
      const response = await client.messages.create({
        model: STORY_MODEL,
        max_tokens: 2048,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: prompt }],
        output_config: { format: { type: "json_schema", schema: STORY_SCHEMA } },
      });

      if (response.stop_reason === "refusal") {
        throw new HttpsError(
          "failed-precondition",
          "We couldn't create that story. Try a gentler theme.",
        );
      }
      const textBlock = response.content.find((b) => b.type === "text");
      if (!textBlock || textBlock.type !== "text") {
        throw new HttpsError("internal", "The story came back empty. Please try again.");
      }
      const parsed = JSON.parse(textBlock.text) as { title?: string; text?: string };
      title = (parsed.title ?? "A Bedtime Story").trim();
      text = (parsed.text ?? "").trim();
      if (!text) {
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
      language: language ?? "English",
      source: "generated",
      model: STORY_MODEL,
      status: "ready",
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("Story generated", { uid, storyId: doc.id, characters: text.length });
    return { storyId: doc.id, title, text };
  },
);
