/**
 * The flag emoji of a country, from its ISO 3166-1 alpha-2 code (p9xte6): each letter becomes
 * its Unicode regional-indicator symbol, and a pair of them is drawn as the flag. Null for
 * anything that is not two letters, so a missing or invented code shows no flag rather than
 * stray letters. Systems without flag glyphs (Windows) draw the two letters instead.
 */
export function flagEmoji(iso2: string | null | undefined): string | null {
  if (!iso2 || !/^[A-Za-z]{2}$/.test(iso2)) return null;
  const REGIONAL_INDICATOR_A = 0x1f1e6;
  return [...iso2.toUpperCase()]
    .map((letter) =>
      String.fromCodePoint(REGIONAL_INDICATOR_A + letter.charCodeAt(0) - 65)
    )
    .join("");
}
