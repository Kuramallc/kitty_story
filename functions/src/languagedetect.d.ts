declare module "languagedetect" {
  class LanguageDetect {
    /** Returns [languageName, score] pairs, highest score first. */
    detect(text: string, limit?: number): [string, number][];
  }
  export = LanguageDetect;
}
