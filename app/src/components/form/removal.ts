import type { TimelinePeriod } from "./field-timeline";

/**
 * What removing a record over a range does to its timeline, as the Remove
 * dialog states it before anything is stored: the parts of the record's
 * values inside [validFrom, validTo] go (removed), the rest stays (kept). A
 * period the range cuts through is split at the range's edges, as the
 * database's removal for a portion splits its rows (STATBUS-611).
 *
 * Dates are ISO yyyy-mm-dd, inclusive; validTo null or "infinity" is open-ended.
 */
export interface RemovalPiece {
  valid_from: string;
  valid_to: string;
  values: Record<string, unknown>;
}

export interface RemovalSummary {
  removed: RemovalPiece[];
  kept: RemovalPiece[];
}

const INFINITY = "infinity";

function shiftDay(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// ISO dates compare as strings; "infinity" is after every date.
const before = (a: string, b: string) => a !== INFINITY && (b === INFINITY || a < b);

export function removalSummary(
  periods: readonly TimelinePeriod[],
  validFrom: string,
  validTo: string | null | undefined
): RemovalSummary {
  const end = validTo || INFINITY;
  const removed: RemovalPiece[] = [];
  const kept: RemovalPiece[] = [];
  for (const p of periods) {
    const piece = (valid_from: string, valid_to: string) => ({ valid_from, valid_to, values: p.values });
    // No overlap: the whole period stays.
    if (before(p.valid_to, validFrom) || before(end, p.valid_from)) {
      kept.push(piece(p.valid_from, p.valid_to));
      continue;
    }
    if (p.valid_from < validFrom) kept.push(piece(p.valid_from, shiftDay(validFrom, -1)));
    removed.push(
      piece(p.valid_from < validFrom ? validFrom : p.valid_from, before(end, p.valid_to) ? end : p.valid_to)
    );
    if (before(end, p.valid_to)) kept.push(piece(shiftDay(end, 1), p.valid_to));
  }
  const order = (a: RemovalPiece, b: RemovalPiece) => (a.valid_from < b.valid_from ? -1 : 1);
  return { removed, kept: kept.sort(order) };
}
