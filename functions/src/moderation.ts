import { getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "./auth";
import { ENFORCE_APP_CHECK, REGION, REPORT_HIDE_THRESHOLD } from "./config";

const BASE = { region: REGION, enforceAppCheck: ENFORCE_APP_CHECK } as const;

/**
 * When a community story collects enough user reports, auto-hide it from Explore
 * pending review. Maintains a denormalized `reportCount` and flips
 * `status` → "under_review" at the threshold (Explore filters status ==
 * "published", so it disappears immediately). Runs with admin privileges.
 */
export const onReportCreated = onDocumentCreated(
  { document: "publishedStories/{storyId}/reports/{reportId}", region: REGION },
  async (event) => {
    const storyRef = getFirestore()
      .collection("publishedStories")
      .doc(event.params.storyId);

    await getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(storyRef);
      if (!snap.exists) return;
      const reportCount = ((snap.get("reportCount") as number | undefined) ?? 0) + 1;
      const update: Record<string, unknown> = { reportCount };
      if (reportCount >= REPORT_HIDE_THRESHOLD && snap.get("status") === "published") {
        update.status = "under_review";
        logger.warn("Community story auto-hidden pending review", {
          storyId: event.params.storyId,
          reportCount,
        });
      }
      tx.update(storyRef, update);
    });
  },
);

type ModerationAction = "remove" | "restore";

interface ModerateStoryData {
  storyId: string;
  action: ModerationAction;
}

/**
 * Admin-only takedown / restore of a community story. Gated by the `admin`
 * custom claim (grant it with scripts/set-admin.ts).
 */
export const moderateStory = onCall<ModerateStoryData>(
  { ...BASE, timeoutSeconds: 30 },
  async (request) => {
    requireAuth(request);
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admins only.");
    }

    const storyId = request.data?.storyId;
    const action = request.data?.action;
    if (typeof storyId !== "string" || storyId.length === 0) {
      throw new HttpsError("invalid-argument", "storyId is required.");
    }
    if (action !== "remove" && action !== "restore") {
      throw new HttpsError("invalid-argument", "action must be 'remove' or 'restore'.");
    }

    const storyRef = getFirestore().collection("publishedStories").doc(storyId);
    if (!(await storyRef.get()).exists) {
      throw new HttpsError("not-found", "Story not found.");
    }

    const update =
      action === "remove"
        ? { status: "removed" }
        : { status: "published", reportCount: 0 };
    await storyRef.update(update);
    logger.info("Community story moderated", { by: request.auth!.uid, storyId, action });
    return { storyId, status: update.status };
  },
);
