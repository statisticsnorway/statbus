import type { TimelinePeriod } from "./field-timeline";
import type { ExistenceSpan } from "./unit-existence";

/**
 * A record's timeline with its holes drawn (owner 2026-11-13).
 *
 * A record that belongs to a unit (a contact, location, activity, statistic)
 * can be missing for part of the unit's life, e.g. after Remove took one year
 * away. The timeline draws each such hole as a period of its own, marked
 * `empty`, so the user sees it, and ticking across it shows that a save fills
 * it. A hole is only where the unit exists (its existence spans): before the
 * unit began or after it ended there is nothing to fill. While the existence
 * is unknown (not read yet, or a field of the unit itself) the periods are
 * returned as they are.
 *
 * Dates are ISO yyyy-mm-dd, valid_to inclusive, "infinity" for open-ended.
 */
const INFINITY = "infinity";

function shift(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
const before = (a: string, b: string) =>
  a !== INFINITY && (b === INFINITY || a < b);
const minEnd = (a: string, b: string) => (before(a, b) ? a : b);
const maxStart = (a: string, b: string) => (a > b ? a : b);

function hole(
  columns: readonly string[],
  valid_from: string,
  valid_to: string
): TimelinePeriod {
  return {
    valid_from,
    valid_to,
    values: Object.fromEntries(columns.map((c) => [c, null])),
    data_source_id: null,
    edit_comment: null,
    edit_by_user_id: null,
    edit_at: null,
    empty: true,
  };
}

export function withGaps(
  periods: readonly TimelinePeriod[],
  existence: readonly ExistenceSpan[] | undefined
): TimelinePeriod[] {
  if (!existence || periods.length === 0) return [...periods];
  const columns = Object.keys(periods[0].values);
  // The stretches the record does not cover, from -inf to +inf.
  const uncovered: { from: string; to: string }[] = [];
  let cursor: string | null = "0001-01-01";
  for (const p of periods) {
    if (cursor && before(cursor, p.valid_from))
      uncovered.push({ from: cursor, to: shift(p.valid_from, -1) });
    cursor = p.valid_to === INFINITY ? null : shift(p.valid_to, 1);
  }
  if (cursor) uncovered.push({ from: cursor, to: INFINITY });
  // Each uncovered stretch, cut to where the unit exists, is a hole.
  const holes = uncovered.flatMap((u) =>
    existence.flatMap((e) => {
      const from = maxStart(u.from, e.validFrom);
      const to = minEnd(u.to, e.validTo);
      return before(to, from) ? [] : [hole(columns, from, to)];
    })
  );
  return [...periods, ...holes].sort((a, b) =>
    a.valid_from < b.valid_from ? -1 : a.valid_from > b.valid_from ? 1 : 0
  );
}
