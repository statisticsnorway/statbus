/**
 * The command palette's search (cmdk `filter`). `value` is the item's visible
 * label and `keywords` are extra words it answers to. An item stays listed only
 * when every typed word either begins a word of the label or keywords, or is
 * the first letters of consecutive label words ("cij" for "Create import job"),
 * so a query never matches letters scattered through unrelated words. The score
 * orders the list: a whole word ranks above a word start, a word start above
 * initials, and an earlier word above a later one. 0 hides the item.
 */
export function paletteFilter(value: string, search: string, keywords: string[] = []): number {
  const label = toWords(value);
  const words = [...label, ...toWords(keywords.join(" "))];
  const typed = search.toLowerCase().split(/\s+/).filter(Boolean);
  if (typed.length === 0) return 1;
  let score = 0;
  for (const t of typed) {
    const start = words.findIndex((w) => w.startsWith(t));
    if (start !== -1) {
      score += (words[start] === t ? 1 : 0.5) / (1 + start * 0.1);
      continue;
    }
    const initials = label.findIndex((_, i) =>
      t.length > 1 && [...t].every((letter, k) => label[i + k]?.startsWith(letter)),
    );
    if (initials === -1) return 0;
    score += 0.25 / (1 + initials * 0.1);
  }
  return score / typed.length;
}

function toWords(text: string): string[] {
  return text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}
