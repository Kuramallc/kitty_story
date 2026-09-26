/**
 * Non-Latin scripts are unambiguous by Unicode block, so we can name the
 * language ourselves and be right. Checked in order, first match wins:
 * Japanese before Chinese since Japanese text almost always mixes in kana
 * even when it's mostly kanji, and Ukrainian-only Cyrillic letters before
 * plain Cyrillic (which defaults to Russian, the most common case).
 */
const SCRIPT_LANGUAGES: [RegExp, string][] = [
  [/\p{Script=Hiragana}|\p{Script=Katakana}/u, "Japanese"],
  [/\p{Script=Han}/u, "Chinese"],
  [/\p{Script=Hangul}/u, "Korean"],
  [/\p{Script=Arabic}/u, "Arabic"],
  [/\p{Script=Hebrew}/u, "Hebrew"],
  [/\p{Script=Devanagari}/u, "Hindi"],
  [/\p{Script=Bengali}/u, "Bengali"],
  [/\p{Script=Thai}/u, "Thai"],
  [/\p{Script=Greek}/u, "Greek"],
  [/[іїєґ]/i, "Ukrainian"],
  [/\p{Script=Cyrillic}/u, "Russian"],
  [/[đơư]|[ạảãầấẩẫậằắẳẵặẹẻẽềếệểễịỉĩọỏõồốộổỗờớợởỡụủũừứựửữỳỷỹ]/i, "Vietnamese"],
];

/**
 * Names the request's language when its script makes that certain, and returns
 * null otherwise. childName is excluded by the caller — a proper noun carries
 * no language signal and only skews the result.
 *
 * We used to run `languagedetect` over Latin-script text as a fallback. It is
 * an n-gram model that needs a paragraph, and these fields hold two or three
 * words, so it was wrong on most ordinary English prompts: "a sleepy bunny"
 * scored Czech, "dinosaurs" Romanian, "a garden" Hausa. Each cleared the
 * confidence bar and produced a story written in that language. No threshold
 * fixes it either, because the scores are not comparable across languages —
 * "a garden" scored 0.444 for Hausa against "the ocean" at 0.497 for English.
 *
 * So for Latin script we say nothing and let the model infer the language from
 * the prompt it can already read, which it does far better than an n-gram
 * model on three words.
 */
export function detectPreferredLanguage(
  theme: string,
  characters: string,
): string | null {
  const text = [theme, characters].filter(Boolean).join(". ");
  for (const [pattern, name] of SCRIPT_LANGUAGES) {
    if (pattern.test(text)) return name;
  }
  return null;
}
