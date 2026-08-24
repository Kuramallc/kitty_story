import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

/**
 * Ensures the caller is authenticated and returns their uid.
 * App Check is enforced separately via the `enforceAppCheck` callable option.
 */
export function requireAuth(request: CallableRequest<unknown>): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  return request.auth.uid;
}

/**
 * Same as [requireAuth], plus a verified email address. Use this for every
 * callable that spends money (ElevenLabs / Anthropic) or publishes to other
 * families — otherwise throwaway signups get an unlimited free tier each.
 *
 * Google and Apple assert the address themselves, so only password signups can
 * be unverified. The client matches on `details.reason`, not the message.
 */
export function requireVerifiedEmail(request: CallableRequest<unknown>): string {
  const uid = requireAuth(request);
  const token = request.auth!.token;
  if (token.firebase?.sign_in_provider === "password" && token.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Please verify your email address to use this feature.",
      { reason: "email-not-verified" },
    );
  }
  return uid;
}
