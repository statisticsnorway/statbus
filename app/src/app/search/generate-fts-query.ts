let wordBoundaryRegex: RegExp;

try {
  /*
   *   (?<=^|\P{L}) is a positive lookbehind that asserts the position is at the start of the string ^ or after a non-letter \P{L}.
   *   [\p{L}\p{N}]+ matches one or more letters or numbers, including Unicode characters.
   *   (?=\P{L}|$) is a lookahead that asserts the position is at the end of the string $ or before a non-letter \P{L}.
   */
  wordBoundaryRegex = new RegExp(
    "(?<=^|\\P{L})[\\p{L}\\p{N}]+(?=\\P{L}|$)",
    "gu"
  );
} catch (e) {
  console.debug(
    "failed to create regex with unicode word boundaries, falling back to ascii word boundaries"
  );
  wordBoundaryRegex = /\b\w+\b/g;
}

export function generateFTSQuery(prompt: string): string {
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) =>
    new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt);
  const uniqueWordsInPrompt = new Set(
    cleanedPrompt.match(wordBoundaryRegex) ?? []
  );
  return [...uniqueWordsInPrompt]
    .map((word) => (isNegated(word) ? `!'${word}':*` : `'${word}':*`))
    .join(" & ");
}
