export function generateFTSQuery(prompt: string): string {
  try {
    const cleanedPrompt = prompt.trim().toLowerCase();

    const negated = (word: string) =>
      new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt);

    const words = new Set(
      cleanedPrompt.match(/(?<=^|\P{L})[\p{L}\p{N}]+(?=\P{L}|$)/gu) ?? []
    );

    return [...words]
      .map((word) => (negated(word) ? `!'${word}':*` : `'${word}':*`))
      .join(" & ");
  } catch (e) {
    return prompt;
  }
}
