/**
 * Where a unit exists, as the spans its rows cover, and the cap that puts on an
 * edit of a record that belongs to it.
 *
 * A contact, location, activity or statistic is valid only where its unit (legal
 * unit or establishment) exists; sql_saga's temporal foreign key (e.g.
 * contact_legal_unit_id_valid) enforces that in the database, accepting a record
 * that any run of the unit's rows covers. The unit's own history is split into
 * many rows, one per change of any of its columns, so where it exists is the
 * union of those rows, never one row. An edit of the record keeps to that
 * existence: it starts no earlier than the unit and ends no later (owner,
 * 2026-11-12, STATBUS-609). The timeline shows where the unit begins and ends.
 *
 * Dates are ISO yyyy-mm-dd. Rows carry valid_until (exclusive); spans carry
 * validTo (inclusive) or "infinity", like the edit's own dates.
 */

const INFINITY = "infinity";

export interface UnitRow {
  valid_from: string;
  valid_until: string;
}

export interface ExistenceSpan {
  validFrom: string;
  validTo: string;
}

function dayBefore(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

// "infinity" sorts after any date; ISO dates compare as strings.
const later = (a: string, b: string) => (a === INFINITY ? a : b === INFINITY ? b : a > b ? a : b);
const earlier = (a: string, b: string) => (a === INFINITY ? b : b === INFINITY ? a : a < b ? a : b);
const isBefore = (a: string, b: string) => a !== b && earlier(a, b) === a;

/** The spans where the unit exists: its rows joined where one ends as the next begins. */
export function unitExistence(rows: readonly UnitRow[]): ExistenceSpan[] {
  const ordered = [...rows].sort((a, b) => (a.valid_from < b.valid_from ? -1 : a.valid_from > b.valid_from ? 1 : 0));
  const spans: { from: string; until: string }[] = [];
  for (const r of ordered) {
    const last = spans[spans.length - 1];
    if (last && !isBefore(last.until, r.valid_from)) last.until = later(last.until, r.valid_until);
    else spans.push({ from: r.valid_from, until: r.valid_until });
  }
  return spans.map((s) => ({ validFrom: s.from, validTo: s.until === INFINITY ? INFINITY : dayBefore(s.until) }));
}

/**
 * The edit's period kept inside the unit's existence: the first span it
 * overlaps, intersected with it. Null when the unit does not exist anywhere in
 * the period.
 */
export function capToExistence(
  existence: readonly ExistenceSpan[],
  validFrom: string,
  validTo: string | null
): ExistenceSpan | null {
  const to = validTo || INFINITY;
  for (const span of existence) {
    const from = later(validFrom, span.validFrom);
    const until = earlier(to, span.validTo);
    if (!isBefore(until, from)) return { validFrom: from, validTo: until };
  }
  return null;
}
