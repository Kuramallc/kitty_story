// One-off: grant (or revoke) the `admin` custom claim so a user can call the
// moderateStory takedown callable. Plain Node ESM so it needs no build step and
// tsc won't bundle it into the deployed functions.
//
// Usage (from functions/):
//   gcloud auth application-default login        # once, for credentials
//   node scripts/set-admin.mjs <uid>             # grant
//   node scripts/set-admin.mjs <uid> --revoke    # revoke
//
// The user must sign out / back in (or refresh their ID token) for the claim to
// take effect on the client.
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const uid = process.argv[2];
const revoke = process.argv.includes("--revoke");

if (!uid || uid.startsWith("--")) {
  console.error("Usage: node scripts/set-admin.mjs <uid> [--revoke]");
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: "kitty-story" });

await getAuth().setCustomUserClaims(uid, revoke ? null : { admin: true });
console.log(`${revoke ? "Revoked" : "Granted"} admin for ${uid}`);
process.exit(0);
