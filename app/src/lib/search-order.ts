/**
 * The order of a search result page, as a PostgREST `order` parameter, and its reversal.
 *
 * The search page reads a page near the end of a long result by asking for the reversed order
 * from the start (reverseParamsForTailPage in @/atoms/search) and reversing the rows it gets.
 * The reversed order must list the same rows in exactly the opposite sequence, so every term
 * flips both its direction and where missing values go: `desc.nullslast` lists units without a
 * value last, so its reversal `asc.nullsfirst` lists them first. PostgreSQL's default for a term
 * without a nulls placement is nulls last for asc and nulls first for desc.
 *
 * Each order the search sends has a statistical_unit index in that order (see
 * admin.create_statistical_unit_ui_indices and test/sql/359); an index serves an order and its
 * exact reversal, read backwards, so a page from the end is as fast as the first page.
 */

type Direction = "asc" | "desc";
type Nulls = "nullsfirst" | "nullslast";

function parseTerm(term: string): { key: string; direction: Direction; nulls: Nulls } | null {
  const parts = term.split(".");
  const directionIndex = parts.findIndex((part) => part === "asc" || part === "desc");
  if (directionIndex < 0) return null;
  const direction = parts[directionIndex] as Direction;
  const nullsPart = parts.slice(directionIndex + 1).find((part) => part === "nullsfirst" || part === "nullslast");
  const nulls = (nullsPart as Nulls | undefined) ?? (direction === "asc" ? "nullslast" : "nullsfirst");
  return { key: parts.slice(0, directionIndex).join("."), direction, nulls };
}

/** One order term reversed: direction and nulls placement both flip. Terms without a direction are kept. */
export function reverseOrderTerm(term: string): string {
  const parsed = parseTerm(term);
  if (!parsed) return term;
  const direction = parsed.direction === "asc" ? "desc" : "asc";
  const nulls = parsed.nulls === "nullslast" ? "nullsfirst" : "nullslast";
  return `${parsed.key}.${direction}.${nulls}`;
}

/** A whole `order` parameter reversed, term by term. */
export function reverseOrder(order: string): string {
  return order.split(",").map(reverseOrderTerm).join(",");
}
