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
