import { initializeApp } from "firebase-admin/app";

initializeApp();

export { deleteAccount } from "./account";
export { createVoiceProfile, deleteVoiceProfile } from "./voice";
export { synthesizeNarration } from "./narration";
export { generateStory } from "./story";
export {
  prepareStoryForPublish,
  publishStory,
  toggleLike,
  addComment,
} from "./community";
export { onReportCreated, moderateStory } from "./moderation";
export { revenueCatWebhook } from "./subscription";
