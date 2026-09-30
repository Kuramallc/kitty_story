/**
 * The requested story length is a cost control as much as a feature: it sets
 * both the word band in the prompt and max_tokens, and Anthropic bills per
 * output token. A caller sending 500 must not buy a 500-minute story.
 *
 * Run: npm --prefix functions test
 */
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { storyLengthMinutes } from "../lib/story.js";

describe("story length", () => {
  test("keeps values inside the supported range", () => {
    assert.equal(storyLengthMinutes(1), 1);
    assert.equal(storyLengthMinutes(5), 5);
  });

  test("clamps anything outside it", () => {
    assert.equal(storyLengthMinutes(0), 1);
    assert.equal(storyLengthMinutes(-4), 1);
    assert.equal(storyLengthMinutes(6), 5);
    assert.equal(storyLengthMinutes(500), 5, "a big number must not buy a big bill");
  });

  test("falls back to the default for anything not a usable number", () => {
    for (const bad of [undefined, null, "3", NaN, Infinity, {}, []]) {
      assert.equal(storyLengthMinutes(bad), 2, `for ${JSON.stringify(bad)}`);
    }
  });

  test("rounds fractional requests", () => {
    assert.equal(storyLengthMinutes(2.4), 2);
    assert.equal(storyLengthMinutes(2.6), 3);
  });
});
