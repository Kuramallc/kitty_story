/**
 * Pins language detection for story generation.
 *
 * The regression this guards: an n-gram fallback used to guess a language for
 * Latin-script prompts and was wrong most of the time on short English input
 * ("a sleepy bunny" -> Czech, "dinosaurs" -> Romanian), which produced whole
 * stories in the wrong language. Latin script must now yield null so the model
 * infers it from the prompt instead.
 *
 * Run: npm --prefix functions test
 */
import assert from "node:assert/strict";
import { test } from "node:test";

import { detectPreferredLanguage } from "../lib/language.js";

test("names the language when the script is unambiguous", () => {
  const cases = [
    ["ひこうきに乗るお話", "", "Japanese"],
    ["小九和小飞机的环游之旅", "", "Chinese"],
    ["잠자리 이야기", "", "Korean"],
    ["قصة قبل النوم", "", "Arabic"],
    ["סיפור לפני השינה", "", "Hebrew"],
    ["सोने की कहानी", "", "Hindi"],
    ["ঘুমের গল্প", "", "Bengali"],
    ["นิทานก่อนนอน", "", "Thai"],
    ["παραμύθι", "", "Greek"],
    ["казка про їжачка", "", "Ukrainian"],
    ["сказка о котёнке", "", "Russian"],
    ["một chú mèo nhỏ", "", "Vietnamese"],
  ];
  for (const [theme, characters, expected] of cases) {
    assert.equal(detectPreferredLanguage(theme, characters), expected, theme);
  }
});

test("Japanese wins over Chinese when kana are present", () => {
  // Japanese text is mostly kanji with kana mixed in; checking Han first would
  // misread it as Chinese.
  assert.equal(detectPreferredLanguage("猫のお話", ""), "Japanese");
  assert.equal(detectPreferredLanguage("小猫的故事", ""), "Chinese");
});

test("Ukrainian wins over Russian on its own letters", () => {
  assert.equal(detectPreferredLanguage("їжачок", ""), "Ukrainian");
  assert.equal(detectPreferredLanguage("ёжик", ""), "Russian");
});

test("Latin script yields null so the model decides", () => {
  // Every one of these was previously misdetected and forced a wrong-language
  // story. Null is the correct answer now.
  for (const theme of [
    "a sleepy bunny",
    "dinosaurs",
    "a garden",
    "space adventure",
    "a brave little train",
    "friendship",
    "A moonlit garden with a cherry tree",
    "un jardín a la luz de la luna", // Spanish: also null, model infers it
    "un jardin au clair de lune",    // French: likewise
  ]) {
    assert.equal(detectPreferredLanguage(theme, ""), null, theme);
  }
});

test("reads the characters field too, and tolerates empties", () => {
  assert.equal(detectPreferredLanguage("", "小九"), "Chinese");
  assert.equal(detectPreferredLanguage("", ""), null);
});
