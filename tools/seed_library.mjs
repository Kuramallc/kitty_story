// Seeds the curated story library into Firestore `stories/` (public-read,
// admin-write — so this runs with a privileged access token, not the app).
//
// Usage (from repo root):
//   node tools/seed_library.mjs
// Auth: uses $ACCESS_TOKEN if set, else `gcloud auth print-access-token`.
// Idempotent — re-running updates the same docs by id.

import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";

const PROJECT = "kitty-story";
const BASE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/stories`;

function accessToken() {
  if (process.env.ACCESS_TOKEN) return process.env.ACCESS_TOKEN.trim();
  try {
    return execSync("gcloud auth print-access-token", { encoding: "utf8" }).trim();
  } catch {
    console.error(
      "No token. Run `gcloud auth login` (or set ACCESS_TOKEN) and retry.",
    );
    process.exit(1);
  }
}

const stories = JSON.parse(
  readFileSync(new URL("./library_stories.json", import.meta.url), "utf8"),
);
const token = accessToken();
const now = new Date().toISOString();

let ok = 0;
for (const s of stories) {
  const fields = {
    title: { stringValue: s.title },
    text: { stringValue: s.text },
    ageRange: { stringValue: s.ageRange },
    source: { stringValue: "library" },
    createdAt: { timestampValue: now },
  };
  const res = await fetch(`${BASE}/${encodeURIComponent(s.id)}`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ fields }),
  });
  if (res.ok) {
    ok++;
    console.log(`OK  ${s.id}`);
  } else {
    console.error(`ERR ${s.id} (${res.status}) ${await res.text()}`);
  }
}
console.log(`\nSeeded ${ok}/${stories.length} library stories.`);
