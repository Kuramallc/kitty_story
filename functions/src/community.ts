import { createHash } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "./auth";
import {
  ANTHROPIC_API_KEY,
  ENFORCE_APP_CHECK,
  MODERATION_MODEL,
  REGION,
} from "./config";
import { enforceQuota } from "./limits";

// Shared callable options.
const BASE = { region: REGION, enforceAppCheck: ENFORCE_APP_CHECK } as const;

interface Tags {
  content: string[];
  style: string[];
  wisdom: string[];
}

interface ModerationResult {
  safe: boolean;
  reason: string;
  tags: Tags;
}

const TAGS_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    content: {
      type: "array",
      items: { type: "string" },
      description: "3-6 lowercase keywords about subject matter (e.g. animals, ocean, friendship).",
    },
    style: {
      type: "array",
      items: { type: "string" },
      description: "1-3 lowercase keywords about tone/style (e.g. soothing, rhyming, whimsical).",
    },
    wisdom: {
      type: "array",
      items: { type: "string" },
      description: "0-3 lowercase keywords about any lesson or value (e.g. kindness, sharing, courage).",
    },
  },
  required: ["content", "style", "wisdom"],
};

const STORY_MODERATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    safe: {
      type: "boolean",
      description: "True only if wholesome and appropriate for young children (ages 2-8).",
    },
    reason: { type: "string", description: "If not safe, one gentle sentence; else empty." },
    tags: TAGS_SCHEMA,
  },
  required: ["safe", "reason", "tags"],
};

const STORY_MODERATION_SYSTEM = `You review short children's bedtime stories for the Kitty Story app, where parents publish stories for other families' young children (ages 2-8).
- safe: true only if the story is wholesome and appropriate — no violence, scary content, romance, profanity, unsafe themes, hate, or anything inappropriate for young kids. Otherwise false.
- reason: if not safe, one gentle sentence; otherwise an empty string.
- tags: concise lowercase keywords describing the story's content (subjects), style (tone), and wisdom (any lesson/value; may be empty).`;

function anthropic(): Anthropic {
  return new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
}

function sha(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

/** Parses the single text block of a structured-output response as JSON. */
function parseJson<T>(response: Anthropic.Message): T {
  const block = response.content.find((b) => b.type === "text");
  if (!block || block.type !== "text") {
    throw new HttpsError("internal", "The check failed. Please try again.");
  }
  return JSON.parse(block.text) as T;
}

async function moderateStory(title: string, text: string): Promise<ModerationResult> {
  const response = await anthropic().messages.create({
    model: MODERATION_MODEL,
    max_tokens: 1024,
    system: STORY_MODERATION_SYSTEM,
    messages: [{ role: "user", content: `Title: ${title}\n\n${text}` }],
    output_config: { format: { type: "json_schema", schema: STORY_MODERATION_SCHEMA } },
  });
  return parseJson<ModerationResult>(response);
}

/** Lowercases, dedupes, length-caps tags and builds the flattened filter array. */
function normalizeTags(raw: Partial<Tags> | undefined): { tags: Tags; allTags: string[] } {
  const clean = (arr: unknown): string[] =>
    Array.isArray(arr)
      ? [
          ...new Set(
            arr
              .filter((t): t is string => typeof t === "string")
              .map((t) => t.trim().toLowerCase())
              .filter((t) => t.length > 0 && t.length <= 30),
          ),
        ].slice(0, 8)
      : [];
  const tags: Tags = {
    content: clean(raw?.content),
    style: clean(raw?.style),
    wisdom: clean(raw?.wisdom),
  };
  const allTags = [...new Set([...tags.content, ...tags.style, ...tags.wisdom])].slice(0, 30);
  return { tags, allTags };
}

function tagCount(t: Partial<Tags> | undefined): number {
  return (t?.content?.length ?? 0) + (t?.style?.length ?? 0) + (t?.wisdom?.length ?? 0);
}

async function loadOwnedStory(uid: string, generatedStoryId: unknown) {
  if (typeof generatedStoryId !== "string" || generatedStoryId.length === 0) {
    throw new HttpsError("invalid-argument", "generatedStoryId is required.");
  }
  const ref = getFirestore()
    .collection("users").doc(uid)
    .collection("generatedStories").doc(generatedStoryId);
  const snap = await ref.get();
  const text = snap.get("text") as string | undefined;
  if (!snap.exists || !text) {
    throw new HttpsError("not-found", "Story not found.");
  }
  return { ref, snap, text, title: (snap.get("title") as string | undefined) ?? "A Bedtime Story" };
}

interface PrepareData { generatedStoryId: string }

/** Moderates a generated story and proposes tags for the publish editor. */
export const prepareStoryForPublish = onCall<PrepareData>(
  { ...BASE, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60, memory: "512MiB" },
  async (request) => {
    const uid = requireAuth(request);
    const { ref, text, title } = await loadOwnedStory(uid, request.data?.generatedStoryId);

    const result = await moderateStory(title, text);
    const { tags } = normalizeTags(result.tags);
    // Cache the verdict so publishStory can skip a second Claude call.
    await ref.set(
      { moderation: { safe: result.safe, textSha: sha(text), at: FieldValue.serverTimestamp() } },
      { merge: true },
    );
    return { safe: result.safe, reason: result.reason, tags };
  },
);

interface PublishData {
  generatedStoryId: string;
  tags?: Partial<Tags>;
}

/** Publishes a generated story to the shared pool (re-validates safety). */
export const publishStory = onCall<PublishData>(
  { ...BASE, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60, memory: "512MiB" },
  async (request) => {
    const uid = requireAuth(request);
    const { ref: genRef, snap, text, title } = await loadOwnedStory(uid, request.data?.generatedStoryId);

    const existing = snap.get("publishedStoryId") as string | undefined;
    if (existing) return { publishedStoryId: existing, alreadyPublished: true };
    await enforceQuota(uid, "publishStory");

    // Trust the cached moderation verdict if the text is unchanged; else re-check.
    const cached = snap.get("moderation") as { safe?: boolean; textSha?: string } | undefined;
    let safe = cached?.safe === true && cached?.textSha === sha(text);
    let proposed: Tags = { content: [], style: [], wisdom: [] };
    if (!safe) {
      const result = await moderateStory(title, text);
      safe = result.safe;
      proposed = result.tags;
    }
    if (!safe) {
      throw new HttpsError(
        "failed-precondition",
        "This story can't be published — it isn't suitable for young children.",
      );
    }

    // Prefer the author's edited tags; fall back to proposed (fetching if needed).
    let chosen: Partial<Tags>;
    if (tagCount(request.data?.tags) > 0) {
      chosen = request.data!.tags!;
    } else if (tagCount(proposed) > 0) {
      chosen = proposed;
    } else {
      chosen = (await moderateStory(title, text)).tags;
    }
    const { tags, allTags } = normalizeTags(chosen);

    const pubRef = getFirestore().collection("publishedStories").doc();
    await pubRef.set({
      title,
      text,
      authorUid: uid,
      tags,
      allTags,
      likeCount: 0,
      commentCount: 0,
      status: "published",
      sourceGeneratedId: genRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });
    await genRef.set({ publishedStoryId: pubRef.id }, { merge: true });
    logger.info("Story published", { uid, publishedStoryId: pubRef.id });
    return { publishedStoryId: pubRef.id, alreadyPublished: false };
  },
);

interface LikeData { publishedStoryId: string }

/** Idempotent like/unlike with a denormalized counter (transactional). */
export const toggleLike = onCall<LikeData>(
  { ...BASE, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request);
    const publishedStoryId = request.data?.publishedStoryId;
    if (typeof publishedStoryId !== "string" || publishedStoryId.length === 0) {
      throw new HttpsError("invalid-argument", "publishedStoryId is required.");
    }
    const db = getFirestore();
    const storyRef = db.collection("publishedStories").doc(publishedStoryId);
    const likeRef = storyRef.collection("likes").doc(uid);

    const liked = await db.runTransaction(async (tx) => {
      const storySnap = await tx.get(storyRef);
      if (!storySnap.exists) throw new HttpsError("not-found", "Story not found.");
      const likeSnap = await tx.get(likeRef);
      if (likeSnap.exists) {
        tx.delete(likeRef);
        tx.update(storyRef, { likeCount: FieldValue.increment(-1) });
        return false;
      }
      tx.set(likeRef, { at: FieldValue.serverTimestamp() });
      tx.update(storyRef, { likeCount: FieldValue.increment(1) });
      return true;
    });
    const after = await storyRef.get();
    return { liked, likeCount: (after.get("likeCount") as number | undefined) ?? 0 };
  },
);

const COMMENT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    safe: { type: "boolean" },
    reason: { type: "string" },
  },
  required: ["safe", "reason"],
};

const COMMENT_MODERATION_SYSTEM = `You moderate short comments on children's bedtime stories in a family app used around young children.
Return safe=false if the comment contains profanity, insults, harassment, hate, sexual or violent content, personal data, links or spam, or anything inappropriate for a kids' space; otherwise safe=true.
reason: one short sentence when not safe, else an empty string.`;

interface CommentData {
  publishedStoryId: string;
  text: string;
}

/** Adds a comment after Claude moderation; rejects unsafe text. */
export const addComment = onCall<CommentData>(
  { ...BASE, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const uid = requireAuth(request);
    await enforceQuota(uid, "addComment");
    const publishedStoryId = request.data?.publishedStoryId;
    const raw = request.data?.text;
    if (
      typeof publishedStoryId !== "string" || publishedStoryId.length === 0 ||
      typeof raw !== "string" || raw.trim().length === 0
    ) {
      throw new HttpsError("invalid-argument", "publishedStoryId and text are required.");
    }
    const text = raw.trim().slice(0, 500);
    const storyRef = getFirestore().collection("publishedStories").doc(publishedStoryId);
    if (!(await storyRef.get()).exists) throw new HttpsError("not-found", "Story not found.");

    const response = await anthropic().messages.create({
      model: MODERATION_MODEL,
      max_tokens: 256,
      system: COMMENT_MODERATION_SYSTEM,
      messages: [{ role: "user", content: text }],
      output_config: { format: { type: "json_schema", schema: COMMENT_SCHEMA } },
    });
    const verdict = parseJson<{ safe: boolean; reason: string }>(response);
    if (!verdict.safe) {
      throw new HttpsError(
        "failed-precondition",
        "That comment can't be posted — let's keep it kind and kid-friendly.",
      );
    }

    const commentRef = storyRef.collection("comments").doc();
    await commentRef.set({
      authorUid: uid,
      text,
      status: "published",
      createdAt: FieldValue.serverTimestamp(),
    });
    await storyRef.update({ commentCount: FieldValue.increment(1) });
    return { commentId: commentRef.id, text };
  },
);
