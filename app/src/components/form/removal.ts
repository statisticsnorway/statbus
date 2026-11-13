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

/** A stretch to remove: ISO dates inclusive, validTo null for open-ended. */
export interface RemovalRun {
  validFrom: string;
  validTo: string | null;
}

/**
 * The stretches Remove mode removes: the ticked pieces (one per frame, in time
 * order) joined where one ends the day before the next begins. A gap between
 * ticked pieces keeps them as separate stretches, so the removal leaves the
 * unticked time in between (owner 2026-11-13).
 */
export function removalRuns(
  pieces: readonly { valid_from: string; valid_to: string }[],
  ticked: readonly number[]
): RemovalRun[] {
  const chosen = [...new Set(ticked)]
    .map((i) => pieces[i])
    .filter(Boolean)
    .sort((a, b) => (a.valid_from < b.valid_from ? -1 : 1));
  const runs: { validFrom: string; validTo: string }[] = [];
  for (const p of chosen) {
    const last = runs[runs.length - 1];
    if (last && last.validTo !== INFINITY && shiftDay(last.validTo, 1) === p.valid_from) {
      last.validTo = p.valid_to;
    } else {
      runs.push({ validFrom: p.valid_from, validTo: p.valid_to });
    }
  }
  return runs.map((r) => ({ validFrom: r.validFrom, validTo: r.validTo === INFINITY ? null : r.validTo }));
}
