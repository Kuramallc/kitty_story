import { initializeApp } from "firebase-admin/app";

initializeApp();

export { createVoiceProfile, deleteVoiceProfile } from "./voice";
export { synthesizeNarration } from "./narration";
export { generateStory } from "./story";
