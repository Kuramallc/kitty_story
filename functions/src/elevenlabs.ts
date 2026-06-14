import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";

import { ELEVENLABS_API_KEY } from "./config";

/** Build a client lazily inside the request so the secret is available. */
export function elevenLabsClient(): ElevenLabsClient {
  return new ElevenLabsClient({ apiKey: ELEVENLABS_API_KEY.value() });
}

/** Drain a web ReadableStream (SDK TTS output) into a single Buffer. */
export async function streamToBuffer(
  stream: ReadableStream<Uint8Array>,
): Promise<Buffer> {
  const chunks: Uint8Array[] = [];
  const reader = stream.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) chunks.push(value);
  }
  return Buffer.concat(chunks);
}
